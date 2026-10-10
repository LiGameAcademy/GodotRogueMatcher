"""One offline entry point: exports -> Reader -> observations -> new workbook."""
from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

from import_sources import Json, canonical, ingest
from model_statistics import VERSION, analyze
from xlsx_append import append_observations, read_auto, read_managed_cells
from verify_workbook import verify


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")


def write_csv(path: Path, rows: list[Json]) -> None:
    keys = list(dict.fromkeys(key for row in rows for key in row)) or ["metric_id"]
    with path.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, keys)
        writer.writeheader()
        for row in rows:
            encoded = {key: canonical(value) if isinstance(value, (dict, list)) else value
                       for key, value in row.items()}
            writer.writerow({key: "'"+value if isinstance(value,str) and value.startswith(("=","+","-","@"))
                             else value for key,value in encoded.items()})


def run(args: argparse.Namespace) -> int:
    output: Path = args.output.resolve()
    workbook: Path = args.workbook.resolve()
    if output.exists():
        raise ValueError("output directory already exists; choose a new directory")
    if not workbook.is_file() or workbook.suffix.lower() != ".xlsx":
        raise ValueError("a readable v0.4 .xlsx workbook is required")
    if any(output == path.resolve() or output.is_relative_to(path.resolve()) for path in args.inputs):
        raise ValueError("output cannot be inside an input directory")
    if args.min_runs < 30 or args.min_events < 100:
        raise ValueError("reference thresholds cannot be below the 30-run / 100-event trial gate")
    output.mkdir(parents=True)
    staging = output / 'normalized_sources'
    manifest = ingest(args.inputs, staging)
    write_json(output / "data_manifest.json", manifest)
    if not manifest["runs"]:
        raise ValueError("no usable event streams; see data_manifest.json")
    project = Path(__file__).resolve().parents[2]
    report = output / "reader"
    process = subprocess.run([str(args.godot), "--headless", "--text-driver", "Dummy",
                              "--log-file", str(output / "godot.log"),
                              "--path", str(project), "-s",
                              "tools/telemetry_analysis/analysis_cli.gd", "--",
                              str(staging), str(report)], capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=300, check=False)
    (output / "reader.log").write_text(process.stdout + process.stderr, encoding="utf-8")
    if (process.returncode not in (0, 1) or "SCRIPT ERROR:" in process.stdout + process.stderr
            or not (report / "summary.json").is_file()):
        raise ValueError("Godot Reader failed; see reader.log")
    summary = json.loads((report / "summary.json").read_text(encoding="utf-8"))
    with (report / "events.csv").open(encoding="utf-8-sig", newline="") as file:
        events = [json.loads(row["event_json"]) for row in csv.DictReader(file)]
    # A malformed schema/sequence is diagnostic-only, not a valid rule prefix.
    bad_runs = {error.get("run_id") for error in summary["errors"]
                if error["reason"] != "incomplete_telemetry_no_complete_ending"}
    events = [event for event in events if event["run_id"] not in bad_runs]
    result = analyze(events, args.min_runs, args.min_events, args.seed, args.bootstrap)
    for row in result["exits"]:
        row["subject"] = "run"
        recovery = manifest["recovered"].get(row["run_id"])
        if recovery and row["status"] == "incomplete":
            row["end_class"] = recovery["summary"].get("end_class", "unexpected_stop")
            row["recovery_source"] = recovery["file"]
    session_seen: set[str] = set()
    for session in manifest["sessions"]:
        records = session["records"]
        session_id = records[0]["payload"].get("session_id")
        if session_id in session_seen:
            continue
        session_seen.add(session_id)
        last = records[-1]
        closed = last["event"] == "session_closed"
        result["exits"].append({"subject":"session","run_id":None,"session_id":session_id,
            "status":"closed" if closed else "not_closed", "end_class":"session_closed" if closed else "not_ended",
            "reason":last["payload"].get("reason","unknown"), "complete":closed,
            "ui":last["payload"].get("ui","unknown"),"stage_id":None,"root_complete":None,
            "since_input_ms":None,"complete_actions":None,"group_hash":None,"source_ref":session["file"]})
    diagnostics = manifest["diagnostics"] + summary["errors"]
    if diagnostics:
        for row in result["metrics"]:
            if row["quality"] == "candidate":
                row["quality"] = "dataset_diagnostics_require_review"
    if args.group and args.group not in result["groups"]:
        write_json(output / "groups.json", result["groups"])
        raise ValueError("selected group was not found; see groups.json")
    candidates: list[Json] = []
    for row in result["metrics"]:
        target = "auto_reference." + row["metric_id"]
        candidates.append({**row, "target": target,
                           "selected": row["group_hash"] == args.group,
                           "dataset_hash": manifest["dataset_hash"]})
    bundle = {**result, "model_inputs": candidates, "manifest": manifest,
              "diagnostics": diagnostics, "selected_group": args.group,
              "previous_auto": read_auto(workbook),
              "previous_cells": read_managed_cells(workbook),
              "source_workbook": str(workbook), "analyzer_version": VERSION}
    write_json(output / "analysis.json", bundle)
    write_json(output / "model_inputs.json", candidates)
    write_json(output / "groups.json", result["groups"])
    write_json(output / "quality_report.json", {"diagnostics": diagnostics,
               "thresholds": result["thresholds"], "runs": result["runs"],
               "limitations": ["能力attempt分母、直接成线时点、完整H反事实尚无采集证据，保留null",
                               "旧human/unknown上下文不作为真人体验或默认参考",
                               "规则目标、难度与技能Resource不由本工具修改"]})
    write_csv(output / "observations.csv", result["metrics"])
    write_csv(output / "exit_observations.csv", result["exits"])
    # Author new sheets via Artifact Tool; append them without rewriting original cells.
    runtime = args.node_runtime or project / ".godot" / "model_runtime"
    if not (runtime / "node_modules" / "@oai" / "artifact-tool").is_dir():
        raise ValueError("missing Artifact Tool runtime junction; see README setup")
    builder = runtime / "write_observations.mjs"
    shutil.copyfile(Path(__file__).with_name("write_observations.mjs"), builder)
    shutil.copyfile(Path(__file__).with_name("reference_updates.mjs"), runtime / "reference_updates.mjs")
    process = subprocess.run([str(args.node), str(builder), str(output / "analysis.json"),
                              str(output / "observations.xlsx")], capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=300, check=False)
    (output / "workbook.log").write_text(process.stdout + process.stderr, encoding="utf-8")
    if process.returncode:
        raise ValueError("Artifact Tool export failed; see workbook.log")
    append_observations(workbook, output / "observations.xlsx", output / "model-observed.xlsx")
    write_json(output / "verification.json", verify(workbook, output / "model-observed.xlsx",
                                                   output / "changes.csv"))
    print(f"{len(result['runs'])} runs, {len(events)} unique events, {len(diagnostics)} diagnostics")
    print(f"Workbook: {output / 'model-observed.xlsx'}")
    return 1 if diagnostics else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--workbook", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--node-runtime", type=Path, help="temporary directory with Artifact Tool node_modules junction")
    parser.add_argument("--group", help="explicit full group hash from groups.json")
    parser.add_argument("--min-runs", type=int, default=30)
    parser.add_argument("--min-events", type=int, default=100)
    parser.add_argument("--seed", type=int, default=17002)
    parser.add_argument("--bootstrap", type=int, default=500)
    args = parser.parse_args()
    if args.bootstrap < 100:
        parser.error("bootstrap must be >=100")
    try:
        return run(args)
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        print(f"Import failed: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
