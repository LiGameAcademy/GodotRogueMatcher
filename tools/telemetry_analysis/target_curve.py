"""Offline reference targets. Never read a live player's score or write live assets."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
from fractions import Fraction
from math import ceil
from pathlib import Path
from typing import Any

from import_sources import canonical, digest, load_json
from model_statistics import quantile

Json = dict[str, Any]
VERSION = "offline-reference-target-v1"
FINGERPRINTS = ("rule_version", "content_version", "config_hash", "offer_version",
                "pressure_version", "strategy_version", "bot_config_hash", "commit_id",
                "collection_config_hash", "build_id")
SCORE_REASONS = {"match", "explosion", "chain_reward", "marked_reward"}


def positive(value: Any, label: str) -> Decimal:
    if isinstance(value, bool):
        raise ValueError(f"{label}: expected positive number")
    try:
        number = Decimal(str(value))
    except InvalidOperation as error:
        raise ValueError(f"{label}: expected positive number") from error
    if not number.is_finite() or number <= 0:
        raise ValueError(f"{label}: expected finite positive number")
    return number


def integer(value: Any, label: str) -> int:
    number = positive(value, label)
    if number != number.to_integral_value():
        raise ValueError(f"{label}: expected positive integer")
    return int(number)


def reference_actions(stage: int, smooth: bool = True) -> int:
    """Trial tempo only; stages 11+ are model cases, not added runtime stages."""
    if isinstance(stage, bool) or not isinstance(stage, int) or stage < 1:
        raise ValueError("stage must be a positive integer")
    if smooth and stage in {4, 11, 12}:
        return {4: 4, 11: 7, 12: 9}[stage]
    return 3 if stage <= 3 else 5 if stage <= 10 else 10


def generate_targets(means: list[Any], difficulty: Any, step: Any,
                     smooth: bool = True) -> list[int] | None:
    scale = positive(difficulty, "difficulty")
    unit = integer(step, "rounding_step")
    targets: list[int] = []
    missing = False
    for stage, mean in enumerate(means, 1):
        if mean is None:
            missing = True  # Unknown is never coerced to zero.
            continue
        try:
            value = mean if isinstance(mean, Fraction) else Fraction(Decimal(str(mean)))
        except (InvalidOperation, ValueError, OverflowError) as error:
            raise ValueError("mu_reference must be numeric") from error
        if isinstance(mean, bool):
            raise ValueError("mu_reference must be numeric")
        if value < 0:
            raise ValueError("mu_reference must be finite and non-negative")
        raw = reference_actions(stage, smooth) * value * Fraction(scale)
        target = ceil(raw / unit) * unit
        if target > 2**63 - 1 or sum(targets) + target > 2**63 - 1:
            raise ValueError("target curve exceeds signed 64-bit score range")
        targets.append(target)
    return None if missing else targets


def validate_profile(profile: Json) -> None:
    for key in ("profile_id", "curve_version"):
        if not isinstance(profile.get(key), str) or not profile[key]:
            raise ValueError(f"missing {key}")
    selected = profile.get("selection", {})
    if not isinstance(selected, dict) or any(not isinstance(selected.get(k), str)
                                           or not selected[k] for k in FINGERPRINTS):
        raise ValueError("selection requires every rule/config/strategy fingerprint")
    if selected["commit_id"] == "unknown":
        raise ValueError("reference commit must be known")
    if not isinstance(profile.get("bot_config"), dict) or not profile["bot_config"]:
        raise ValueError("reference needs explicit replayed bot parameters")
    targets = profile.get("fallback_targets")
    intervals = profile.get("pressure_intervals")
    if (not isinstance(targets, list) or not isinstance(intervals, list)
            or not 1 <= len(targets) <= 8 or len(intervals) != len(targets)):
        raise ValueError("finite runtime fallback needs 1..8 targets and matching intervals")
    for value in targets + intervals:
        if not isinstance(value, int) or isinstance(value, bool):
            raise ValueError("fallback targets and intervals must be integers")
        integer(value, "fallback target / interval")
    if sum(targets) > 2**63 - 1:
        raise ValueError("fallback targets exceed signed 64-bit score range")
    base = integer(profile.get("base_refill", 3), "base_refill")
    maximum = integer(profile.get("maximum_refill", 6), "maximum_refill")
    if not 1 <= base <= maximum <= 6:
        raise ValueError("invalid refill range")
    positive(profile.get("difficulty", 1), "difficulty")
    integer(profile.get("rounding_step", 5), "rounding_step")
    if not isinstance(profile.get("smooth", True), bool):
        raise ValueError("smooth must be boolean")
    if integer(profile.get("min_seeds", 30), "min_seeds") < 30:
        raise ValueError("reference requires at least 30 independent bot seeds")
    if integer(profile.get("min_actions", 100), "min_actions") < 100:
        raise ValueError("reference requires at least 100 complete actions per stage")


def verified_runs(report: Json, profile: Json) -> set[str]:
    """#18 batch reports only: mixed groups and groups with errors are excluded."""
    if report.get("protocol") != "pressure-batch-v1":
        raise ValueError("expected pressure-batch-v1 replay report")
    selection = profile["selection"]
    result: set[str] = set()
    for group in report.get("groups", {}).values():
        if (group.get("errors") or group.get("mode") != "stage_challenge"
                or group.get("config_hash") != selection["config_hash"]
                or group.get("rules_version") != selection["rule_version"]
                or group.get("strategy") != selection["strategy_version"]
                # Godot and Python float formatting differs; compare canonical values,
                # while the recorded Godot bot hash is matched on every event below.
                or canonical(group.get("bot_config")) != canonical(profile["bot_config"])
                or group.get("commit_id") != selection["commit_id"]):
            continue
        result.update(row["run_id"] for row in group.get("runs", [])
                      if row.get("status") in {"completed", "abandoned", "censored"})
    return result


def analyze(events: list[Json], profile: Json, replayed: set[str], source_hash: str = "") -> Json:
    validate_profile(profile)
    selection = profile["selection"]
    selected: dict[str, Json] = {}
    excluded: Counter[str] = Counter()
    for event in events:
        normal = (event.get("schema_version") == "2" and event.get("source") == "bot"
                  and event.get("initialization") == "normal"
                  and event.get("collection_context") == "bot_batch"
                  and event.get("mode_id") == "stage_challenge"
                  and not event.get("experiment_id") and not event.get("parent_run_id"))
        if not normal or any(event.get(key) != selection[key] for key in FINGERPRINTS):
            excluded["different_group_or_fixture"] += 1
            continue
        if event.get("run_id") not in replayed:
            excluded["missing_exact_replay"] += 1
            continue
        identifier = event["event_id"]
        if identifier in selected and canonical(selected[identifier]) != canonical(event):
            raise ValueError("conflicting duplicate event")
        selected[identifier] = event
    streams: dict[str, list[Json]] = defaultdict(list)
    for event in selected.values():
        streams[event["run_id"]].append(event)
    count = len(profile["fallback_targets"])
    stages: list[Json] = []
    for stage in range(1, count + 1):
        scores: list[int] = []
        drift: list[int] = []
        actions: set[tuple[str, str]] = set()
        seeds: set[str] = set()
        builds: Counter[str] = Counter()
        reached: set[str] = set()
        passed: dict[str, int] = {}
        within = 0
        endings: Counter[str] = Counter()
        for run, stream in streams.items():
            stream.sort(key=lambda e: int(e["telemetry_seq"]))
            end = next((e["payload"] for e in reversed(stream)
                        if e["event_name"] == "run_ended"), {})
            if end.get("status") == "rule_error":
                continue
            for event in stream:
                payload = event["payload"]
                for observation in (payload.get("stage_before", {}),
                                    payload.get("stage_after", {}), payload.get("stage", {}),
                                    payload.get("initial_observation", {}).get("stage", {})):
                    if observation.get("enabled") and int(observation.get("stage_id", 0)) == stage:
                        reached.add(run)
                if event["event_name"] == "stage_goal_completed":
                    result = payload["result"]
                    if int(result["stage_id"]) == stage:
                        reached.add(run)
                        passed[run] = int(result["used_actions"])
                if event["event_name"] != "action_resolved" or not payload.get("complete"):
                    continue
                if int(payload.get("stage_before", {}).get("stage_id", 0)) != stage:
                    continue
                key = (run, str(event["root_action_id"]))
                if key in actions:
                    raise ValueError("duplicate complete action")
                actions.add(key)
                seeds.add(str(event["seed"]))
                entries = payload["ledger_entries"]
                score = sum(int(entry["final_score"]) for entry in entries
                            if entry["reason"] in SCORE_REASONS
                            and str(entry["action_id"]) == key[1])
                scores.append(score)
                created, removed = int(payload["created"]), int(payload["removed"])
                if (payload.get("space_consistent") is not True
                        or int(payload["occupied_after"]) - int(payload["occupied_before"]) != created - removed):
                    raise ValueError("inconsistent full-action space accounting")
                drift.append(created - removed)
                builds[digest(payload["build_before"])] += 1
            if run in reached:
                if run in passed:
                    endings["passed"] += 1
                    within += passed[run] <= reference_actions(stage, profile.get("smooth", True))
                elif end.get("status") == "completed" and end.get("reason") == "board_full":
                    endings["board_full_unmet"] += 1
                elif end.get("status") == "abandoned":
                    endings["abandoned"] += 1
                elif end.get("status") == "censored":
                    endings["tool_censored"] += 1
                else:
                    endings["incomplete_or_unknown"] += 1
        enough = len(seeds) >= profile.get("min_seeds", 30) and len(actions) >= profile.get("min_actions", 100)
        mu = sum(scores) / len(scores) if scores else None
        stages.append({"stage_id": stage, "reference_actions": reference_actions(stage, profile.get("smooth", True)),
                       "mu_reference_observed": mu, "space_drift_observed": sum(drift) / len(drift) if drift else None,
                       "eligible_score_total": sum(scores),
                       "complete_actions": len(actions), "independent_seeds": len(seeds),
                       "quality": "candidate" if enough else "insufficient_coverage",
                       "build_exposure": dict(builds), "observed_reached": len(reached),
                       "endings": dict(endings), "passed_actions_p50_p90": [quantile(list(passed.values()), q) for q in (0.5, 0.9)],
                       "within_reference_actions": within,
                       "within_reference_actions_rate_known": within / (endings["passed"] + endings["board_full_unmet"])
                       if endings["passed"] + endings["board_full_unmet"] else None})
    # Exact integer score / action ratio avoids rounding 5/3 * R=3 up to 10.
    means = [Fraction(row["eligible_score_total"], row["complete_actions"]) if row["quality"] == "candidate" else None for row in stages]
    candidate = generate_targets(means, profile.get("difficulty", 1), profile.get("rounding_step", 5), profile.get("smooth", True))
    reason = "insufficient_stage_reference" if candidate is None else "zero_score_reference" if 0 in candidate else "candidate_needs_review"
    use_reference = reason == "candidate_needs_review"
    dataset = {"reader_sha256": source_hash, "event_ids": sorted(selected), "selection": selection} if source_hash else sorted(selected.values(), key=lambda e: e["event_id"])
    return {"protocol": VERSION, "profile": profile, "dataset_hash": digest(dataset),
            "stages": stages, "excluded_events": dict(excluded), "candidate_targets": candidate,
            "exported_targets": candidate if use_reference else profile["fallback_targets"],
            "target_policy": "offline_reference" if use_reference else "fixed_fallback", "reason": reason,
            "limitations": "Observed old-target distributions are not a candidate-curve simulation or player expectation. R is not a death deadline. Space/extra choices are not unconditional score multipliers."}


def resource_text(report: Json) -> str:
    profile = report["profile"]
    reference = report["target_policy"] == "offline_reference"
    fields: Json = {"curve_version": profile["curve_version"] if reference else "fixed-8-targets-v1",
                    "reference_profile": profile["profile_id"], "reference_dataset_hash": report["dataset_hash"],
                    "reference_rule_version": profile["selection"]["rule_version"], "target_policy": report["target_policy"]}
    lines = ['[gd_resource type="Resource" script_class="StageConfig" load_steps=2 format=3]',
             '[ext_resource type="Script" path="res://gameplay/progression/stages/stage_config.gd" id="1"]',
             '[resource]', 'script = ExtResource("1")',
             f'targets = Array[int]({report["exported_targets"]})',
             f'pressure_intervals = Array[int]({profile["pressure_intervals"]})',
             f'base_refill = {profile.get("base_refill", 3)}', f'maximum_refill = {profile.get("maximum_refill", 6)}']
    lines.extend(f"{key} = {json.dumps(value, ensure_ascii=False)}" for key, value in fields.items())
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reader", type=Path, help="existing Godot Reader output directory")
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--replay-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="new directory; never a live resource path")
    args = parser.parse_args()
    try:
        output = args.output.resolve()
        project = Path(__file__).resolve().parents[2]
        if (output.exists() or any(output.is_relative_to(project / part) for part in ("gameplay", "ui", "services", "addons"))
                or output.is_relative_to(args.reader.resolve())):
            raise ValueError("output must be new and outside live assets and Reader input")
        profile = load_json(args.profile.read_text(encoding="utf-8"))
        validate_profile(profile)
        summary = load_json((args.reader / "summary.json").read_text(encoding="utf-8"))
        if summary.get("errors") != [] or summary.get("schema") != "telemetry-report-v1":
            raise ValueError("Reader must have a valid report schema and no diagnostics")
        source = args.reader / "events.csv"
        with source.open("rb") as file:
            source_hash = hashlib.file_digest(file, "sha256").hexdigest()
        # A 100-run Reader CSV is 242 MB. Keep only facts this model consumes,
        # while the source-file hash preserves provenance of all validated rows.
        events: list[Json] = []
        rows = 0
        needed = {"action_resolved", "stage_goal_completed", "run_started", "run_ended", "ui_observed"}
        with source.open(encoding="utf-8-sig", newline="") as file:
            for row in csv.DictReader(file):
                rows += 1
                if row["event_name"] not in needed:
                    continue
                event = load_json(row["event_json"])
                payload = event["payload"]
                if event["event_name"] == "run_started":
                    event["payload"] = {"initial_observation": {"stage": payload["initial_observation"]["stage"]}}
                elif event["event_name"] == "ui_observed":
                    event["payload"] = {"stage": payload.get("stage", {})}
                events.append(event)
        if rows != summary["events"]:
            raise ValueError("Reader event count mismatch")
        replay = load_json(args.replay_report.read_text(encoding="utf-8"))
        report = analyze(events, profile, verified_runs(replay, profile), source_hash)
        report["input_fingerprints"] = {"reader_events_sha256": source_hash, "reader_summary": digest(summary),
                                        "replay_report": digest(replay), "profile": digest(profile)}
        output.mkdir(parents=True)
        (output / "target_curve.json").write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
        (output / "stage_config_candidate.tres").write_text(resource_text(report), encoding="utf-8")
        print(json.dumps({"reason": report["reason"], "targets": report["exported_targets"], "output": str(output)}, ensure_ascii=False))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"target curve failed: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
