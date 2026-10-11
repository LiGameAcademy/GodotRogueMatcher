"""Offline package ingestion. Godot's existing Reader remains the schema validator."""
from __future__ import annotations

import csv
import hashlib
import io
import json
import zipfile
from pathlib import Path
from typing import Any

Json = dict[str, Any]
MAX_FILE = 128 * 1024 * 1024
MAX_PACKAGE = 512 * 1024 * 1024
STABLE_ENVELOPE = ("schema_version", "run_id", "session_id", "source", "initialization",
    "mode_id", "collection_context", "rule_version", "content_version", "offer_version",
    "build_id", "commit_id", "config_hash", "pressure_version", "collection_config_hash",
    "strategy_version", "bot_config_hash", "experiment_id", "variant_id", "seed", "parent_run_id")


def canonical(value: Any) -> str:
    # Godot JSON numbers round-trip through float; integral floats equal integers.
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    elif isinstance(value, dict):
        value = {k: json.loads(canonical(v)) for k, v in value.items()}
    elif isinstance(value, list):
        value = [json.loads(canonical(v)) for v in value]
    return json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False,
                      separators=(",", ":"))


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def load_json(text: str) -> Any:
    def invalid(value: str) -> None:
        raise ValueError(f"non-finite JSON: {value}")
    return json.loads(text, parse_constant=invalid)


def read_members(paths: list[Path]) -> list[tuple[str, bytes]]:
    result: list[tuple[str, bytes]] = []
    total = 0
    for path in paths:
        if not path.exists():
            raise ValueError(f"input source does not exist: {path}")
        files = sorted(path.rglob("*")) if path.is_dir() else [path]
        for file in files:
            if not file.is_file():
                continue
            if file.suffix.lower() == ".zip":
                if not zipfile.is_zipfile(file):
                    raise ValueError(f"invalid ZIP file: {file}")
                with zipfile.ZipFile(file) as archive:
                    for member in archive.infolist():
                        if member.is_dir():
                            continue
                        if member.file_size > MAX_FILE:
                            raise ValueError(f"oversized ZIP member: {member.filename}")
                        total += member.file_size
                        if total > MAX_PACKAGE:
                            raise ValueError("package exceeds 512 MiB")
                        # Read bytes only; never extract paths supplied by the ZIP.
                        try:
                            result.append((f"{file.resolve()}!{member.filename}", archive.read(member)))
                        except (zipfile.BadZipFile, RuntimeError) as error:
                            raise ValueError(f"unreadable ZIP member: {member.filename}: {error}") from error
            elif file.suffix.lower() in {".jsonl", ".csv", ".json"}:
                if file.stat().st_size > MAX_FILE:
                    raise ValueError(f"oversized source: {file}")
                total += file.stat().st_size
                if total > MAX_PACKAGE:
                    raise ValueError("package exceeds 512 MiB")
                result.append((str(file.resolve()), file.read_bytes()))
    return result


def ingest(paths: list[Path], destination: Path) -> Json:
    """Reject an entire conflicting run; retain diagnosable valid prefixes."""
    events: dict[str, Json] = {}
    origins: dict[str, list[str]] = {}
    rejected: set[str] = set()
    diagnostics: list[Json] = []
    inventory: list[Json] = []
    summaries: list[tuple[str, Json]] = []
    headers: dict[str, Json] = {}
    sessions: dict[str, Json] = {}
    bad_sessions: set[str] = set()
    recovered: dict[str, Json] = {}
    for name, raw in read_members(paths):
        inventory.append({"path": name, "sha256": hashlib.sha256(raw).hexdigest(),
                          "bytes": len(raw)})
        values: list[tuple[int, Json]] = []
        try:
            text = raw.decode("utf-8-sig")
            if name.lower().endswith(".jsonl"):
                for line_number, line in enumerate(text.splitlines(keepends=True), 1):
                    if not line.endswith(("\n", "\r")):
                        diagnostics.append({"file": name, "line": line_number,
                                            "reason": "incomplete_last_line"})
                        break
                    try:
                        event = load_json(line)
                        if not isinstance(event, dict):
                            raise ValueError("event is not an object")
                        values.append((line_number, event))
                    except (ValueError, TypeError) as error:
                        diagnostics.append({"file": name, "line": line_number,
                                            "reason": str(error)})
                        break
            elif name.lower().endswith("events.csv"):
                reader = csv.DictReader(io.StringIO(text))
                if "event_json" not in (reader.fieldnames or []):
                    diagnostics.append({"file": name, "reason": "lossy_csv_requires_original_jsonl"})
                    continue
                for line_number, row in enumerate(reader, 2):
                    event = load_json(row["event_json"])
                    if not isinstance(event, dict):
                        raise ValueError("event_json is not an object")
                    values.append((line_number, event))
                values.sort(key=lambda item: (item[1].get("run_id", ""), int(item[1].get("telemetry_seq", "0"))))
            elif name.lower().endswith(".json"):
                summary = load_json(text)
                if isinstance(summary, dict) and "run_id" in summary:
                    if not isinstance(summary["run_id"],str):
                        raise ValueError("invalid_summary_run_id")
                    summaries.append((name, summary))
                continue
            else:
                continue  # Other six CSVs are projections, never extra observations.
        except (ValueError, TypeError, UnicodeError, csv.Error, KeyError) as error:
            diagnostics.append({"file": name, "reason": str(error)})
        if values and values[0][1].get("session_schema"):
            inventory[-1]["kind"] = "session_evidence"
            rows = [row for _, row in values]
            first_payload = rows[0].get("payload")
            identifier = first_payload.get("session_id") if isinstance(first_payload,dict) else None
            if (not isinstance(identifier,str) or
                    any(not isinstance(row.get("payload"),dict) or not isinstance(row.get("event"),str)
                        or row.get("session_schema") != "collection-session-v1" or row.get("seq") != str(i)
                        for i, row in enumerate(rows, 1))):
                diagnostics.append({"file":name,"reason":"invalid_session_sequence_or_schema"})
            elif identifier in sessions:
                old = sessions[identifier]["records"]
                common = min(len(old),len(rows))
                if canonical(old[:common]) != canonical(rows[:common]):
                    bad_sessions.add(identifier)
                    diagnostics.append({"file":name,"reason":"conflicting_session_records"})
                elif len(rows) > len(old):
                    sessions[identifier] = {"file":name,"records":rows}
            else:
                sessions[identifier] = {"file":name,"records":rows}
            continue
        if values and values[0][1].get("kind") == "Header":
            inventory[-1]["kind"] = "rule_record_evidence_not_telemetry"
            continue
        local_run: str | None = None
        last_sequence = 0
        local_seen: set[str] = set()
        ended = False
        for line_number, event in values:
            run = event.get("run_id")
            event_id = event.get("event_id")
            try:
                if not isinstance(run, str) or not isinstance(event_id, str):
                    raise ValueError("invalid_event_identity")
                sequence = int(event["telemetry_seq"])
                if local_run is not None and run != local_run and not name.lower().endswith("events.csv"):
                    raise ValueError("mixed_run_file")
                if name.lower().endswith("events.csv") and run != local_run:
                    local_seen, last_sequence, ended = set(), 0, False
                if event_id not in local_seen:
                    if ended or sequence != last_sequence + 1:
                        raise ValueError("sequence_gap_or_events_after_ending")
                    if sequence == 1 and event.get("event_name") != "run_started":
                        raise ValueError("missing_run_started")
                    last_sequence = sequence
                    ended = event.get("event_name") == "run_ended"
                local_run = run
                local_seen.add(event_id)
                metadata = {key:event.get(key) for key in STABLE_ENVELOPE}
                if run in headers and headers[run] != metadata:
                    raise ValueError("conflicting_run_metadata")
                headers.setdefault(run, metadata)
                if event_id in events and canonical(events[event_id]) != canonical(event):
                    rejected.add(run)
                    diagnostics.append({"file": name, "run_id": run, "reason": "conflicting_event_id"})
                    continue
                events[event_id] = event
                origins.setdefault(event_id, []).append(f"{name}:{line_number}")
            except (ValueError, KeyError, TypeError) as error:
                if isinstance(run, str):
                    rejected.add(run)
                diagnostics.append({"file": name, "line": line_number, "run_id": run,
                                    "reason": str(error)})
                break
    for name, summary in summaries:
        run = summary["run_id"]
        endings = [e["payload"] for e in events.values()
                   if e["run_id"] == run and e["event_name"] == "run_ended"]
        if not endings:
            prefix = [e for e in events.values() if e["run_id"] == run]
            last_sequence = max((int(e["telemetry_seq"]) for e in prefix),default=0)
            if (summary.get("summary_version") == "recovered-run-summary-v2" and prefix and
                    summary.get("last_persisted_seq") == str(last_sequence)):
                recovered[run] = {"file":name,"summary":summary}
            else:
                diagnostics.append({"file": name, "run_id": run, "reason": "summary_without_events"})
        elif any(key in summary and canonical(summary[key]) != canonical(endings[0].get(key))
                 for key in ("score", "status", "reason", "record_complete")):
            rejected.add(run)
            diagnostics.append({"file": name, "run_id": run, "reason": "summary_event_conflict"})
    grouped: dict[str, list[Json]] = {}
    for event in events.values():
        if event["run_id"] not in rejected:
            grouped.setdefault(event["run_id"], []).append(event)
    destination.mkdir(parents=True, exist_ok=True)
    for run, rows in grouped.items():
        rows.sort(key=lambda row: int(row["telemetry_seq"]))
        # Hash filenames so even invalid IDs cannot escape the staging directory.
        filename = digest(run) + ".jsonl"
        (destination / filename).write_text("".join(canonical(e) + "\n" for e in rows), encoding="utf-8")
    normalized = sorted((canonical(e) for e in events.values() if e["run_id"] not in rejected))
    valid_sessions = [s for key,s in sorted(sessions.items()) if key not in bad_sessions]
    evidence_hash = digest([normalized, [s["records"] for s in valid_sessions],
                            {key:value["summary"] for key,value in sorted(recovered.items())}])
    return {"dataset_hash": digest(normalized), "evidence_hash":evidence_hash,
            "files": inventory, "diagnostics": diagnostics,
            "rejected_runs": sorted(rejected), "source_refs": origins,
            "sessions":valid_sessions,"recovered":recovered,
            "runs": len(grouped), "events": len(normalized)}
