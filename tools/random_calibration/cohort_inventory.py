"""Inventory batch-run identities and seed pairing without estimating parameter effects."""

from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path
import re
from typing import Any

from calibration_plan import OFFER_VERSION, RULE_VERSION, seed_value, validate_plan
from report_preflight import MAX_ARTIFACT_BYTES, MAX_ARTIFACTS, MAX_TOTAL_BYTES, read_object

DIMENSIONS = ("source", "rules_version", "strategy", "config_hash", "mode_id", "content_version", "offer_version", "build", "bot_config_hash")
CONTEXT = tuple(key for key in DIMENSIONS if key != "config_hash")
REQUIRED = set(DIMENSIONS) | {"run_id", "seed", "status", "reason", "replay_error", "record_complete"}
MISSING_EVIDENCE = ["runtime_parameter_binding_unverified", "telemetry_schema_not_in_batch_index",
                    "initialization_and_parent_lineage_not_in_batch_index", "engine_build_not_in_batch_index"]


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def _read_csv(path: Path) -> tuple[list[dict[str, str]], str]:
    with path.open("rb") as source:
        raw = source.read(MAX_ARTIFACT_BYTES + 1)
    if len(raw) > MAX_ARTIFACT_BYTES:
        raise ValueError("batch index exceeds 8 MiB")
    try:
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig"), newline=""), strict=True)
        fields = reader.fieldnames
        if not fields or len(fields) > 64 or len(fields) != len(set(fields)) or not REQUIRED.issubset(fields):
            raise ValueError("expected RunAnalysis runs.csv with seed and quality columns")
        rows: list[dict[str, str]] = []
        for row in reader:
            if None in row or any(value is None for value in row.values()):
                raise ValueError("CSV row width does not match header")
            rows.append(row)
            if len(rows) > 10000:
                raise ValueError("batch index exceeds 10000 rows")
    except csv.Error as error:
        raise ValueError("invalid batch CSV: " + str(error)) from error
    if not rows:
        raise ValueError("batch index contains no run rows")
    return rows, hashlib.sha256(raw).hexdigest()


def inventory(plan: dict[str, Any], plan_hash: str, path: Path, phase: str, variant: str) -> dict[str, Any]:
    pending = validate_plan(plan)
    if phase not in plan["seeds"]:
        raise ValueError("unknown experiment phase")
    labels = {row["id"] for row in plan["related_scan"]} | {"baseline_observed"}
    if variant not in labels:
        raise ValueError("variant must be a registered related-scan label or baseline_observed")
    rows, source_hash = _read_csv(path)
    expected = set(plan["seeds"][phase])
    records: dict[str, dict[str, Any]] = {}
    groups: dict[str, dict[str, Any]] = {}
    seed_runs: dict[str, list[str]] = {}
    duplicates = 0
    for row in rows:
        run_id = row["run_id"]
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", run_id):
            raise ValueError("invalid batch run_id")
        seed_value(row["seed"])
        if row["rules_version"] != RULE_VERSION or row["offer_version"] != OFFER_VERSION:
            raise ValueError("unsupported rules or offer version in batch index")
        if any(row[key] in ("", "unknown") for key in DIMENSIONS):
            raise ValueError("batch index lacks a required dimension")
        if row["record_complete"] not in ("true", "false") or row["status"] not in ("completed", "censored", "abandoned", "rule_error", "incomplete"):
            raise ValueError("invalid record quality fields")
        row_hash = _digest(row)
        if run_id in records:
            if records[run_id]["row_sha256"] != row_hash:
                raise ValueError("conflicting batch rows for run_id: " + run_id)
            duplicates += 1
            continue
        dimensions = {key: row[key] for key in DIMENSIONS}
        group_key = _digest(dimensions)
        if group_key not in groups:
            groups[group_key] = {"dimensions": dimensions, "run_ids": []}
        groups[group_key]["run_ids"].append(run_id)
        issues = []
        if row["source"] != "bot":
            issues.append("not_bot_source")
        if row["record_complete"] != "true":
            issues.append("record_incomplete")
        if row["replay_error"]:
            issues.append("replay_error")
        if row["status"] != "completed":
            issues.append("censored_or_nonterminal")
        elif row["reason"] not in ("board_full", "challenge_completed"):
            issues.append("unknown_completed_endpoint")
        records[run_id] = {"run_id": run_id, "seed": row["seed"], "group": group_key,
                           "status": row["status"], "reason": row["reason"], "issues": issues, "row_sha256": row_hash}
        seed_runs.setdefault(row["seed"], []).append(run_id)
    repeated = {seed: ids for seed, ids in seed_runs.items() if len(ids) > 1}
    qualified = {record["seed"] for record in records.values() if not record["issues"] and record["seed"] not in repeated}
    observed = set(seed_runs)
    errors = []
    if len(groups) != 1:
        errors.append("mixed_configuration_or_strategy_groups")
    if repeated:
        errors.append("multiple_run_ids_for_same_seed")
    if observed - expected:
        errors.append("unplanned_seeds")
    if expected - qualified:
        errors.append("missing_metadata_qualified_seeds")
    if any(record["issues"] for record in records.values()):
        errors.append("run_quality_diagnostics")
    def order(values: set[str]) -> list[str]:
        return sorted(values, key=int)
    return {"schema": "random-cohort-inventory-v1", "status": "preparation_only", "plan_sha256": plan_hash,
            "phase": phase, "variant": {"label": variant, "binding_status": "declared_not_runtime_verified", "actual_parameters": None},
            "source": {"path": str(path.resolve()), "sha256": source_hash}, "groups": groups,
            "expected_seeds": order(expected), "observed_seeds": order(observed), "metadata_qualified_seeds": order(qualified),
            "missing_seeds": order(expected - qualified), "extra_seeds": order(observed - expected),
            "repeated_seeds": repeated, "duplicate_input_rows": duplicates, "records": list(records.values()),
            "seed_inventory_complete": not errors, "errors": errors, "pending": pending + MISSING_EVIDENCE,
            "independent_parent_runs": None, "telemetry_coverage_verified": False,
            "ready_to_select_parameters": False, "parameter_acceptance": None}


def _check_records(item: dict[str, Any]) -> set[str]:
    """Check exported identity/quality consistency, without trusting it as raw telemetry."""
    records = item.get("records")
    if not isinstance(records, list) or not 1 <= len(records) <= 10000:
        raise ValueError("missing inventory records")
    ids: set[str] = set()
    seed_runs: dict[str, list[str]] = {}
    grouped: dict[str, list[str]] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("invalid inventory record")
        run_id = record.get("run_id")
        group = record.get("group")
        issues = record.get("issues")
        if not isinstance(run_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", run_id) or run_id in ids:
            raise ValueError("invalid or duplicate inventory run_id")
        if not isinstance(group, str) or group not in item["groups"] or not isinstance(issues, list) or any(not isinstance(issue, str) for issue in issues):
            raise ValueError("invalid inventory record group or quality")
        seed_value(record.get("seed"))
        if not issues and (record.get("status") != "completed" or record.get("reason") not in ("board_full", "challenge_completed")):
            raise ValueError("record endpoint contradicts quality")
        ids.add(run_id)
        seed_runs.setdefault(record["seed"], []).append(run_id)
        grouped.setdefault(group, []).append(run_id)
    for key, group in item["groups"].items():
        if not isinstance(group, dict) or group.get("run_ids") != grouped.get(key):
            raise ValueError("inventory group membership mismatch")
    repeated = {seed: runs for seed, runs in seed_runs.items() if len(runs) > 1}
    qualified = {record["seed"] for record in records if not record["issues"] and record["seed"] not in repeated}
    expected = set(item["expected_seeds"])
    derived = {"observed_seeds": sorted(seed_runs, key=int), "metadata_qualified_seeds": sorted(qualified, key=int),
               "missing_seeds": sorted(expected - qualified, key=int), "extra_seeds": sorted(set(seed_runs) - expected, key=int)}
    if any(item.get(key) != value for key, value in derived.items()) or item.get("repeated_seeds") != repeated:
        raise ValueError("inventory seed fields contradict records")
    complete = len(item["groups"]) == 1 and not repeated and set(seed_runs) == expected and qualified == expected
    if item["seed_inventory_complete"] != complete or bool(item["errors"]) == complete:
        raise ValueError("inventory completeness contradicts records")
    return ids


def compare(plan: dict[str, Any], plan_hash: str, paths: list[Path]) -> dict[str, Any]:
    pending = validate_plan(plan)
    if not 2 <= len(paths) <= MAX_ARTIFACTS:
        raise ValueError("provide 2 to 64 cohort inventory files")
    cohorts = []
    seen: set[str] = set()
    total_bytes = 0
    run_ids: set[str] = set()
    overlap = False
    for path in paths:
        item, digest, size = read_object(path)
        total_bytes += size
        if total_bytes > MAX_TOTAL_BYTES:
            raise ValueError("cohort inputs exceed the 32 MiB budget")
        if digest in seen:
            continue
        seen.add(digest)
        if item.get("schema") != "random-cohort-inventory-v1" or item.get("plan_sha256") != plan_hash:
            raise ValueError("inventory schema or plan identity mismatch")
        phase = item.get("phase")
        if not isinstance(phase, str) or phase not in plan["seeds"]:
            raise ValueError("inventory has unknown phase")
        for key in ("expected_seeds", "metadata_qualified_seeds"):
            values = item.get(key)
            if not isinstance(values, list) or any(not isinstance(seed, str) for seed in values):
                raise ValueError("invalid inventory seed set")
            if len({seed_value(seed) for seed in values}) != len(values):
                raise ValueError("duplicate inventory seed")
        if set(item["expected_seeds"]) != set(plan["seeds"][phase]):
            raise ValueError("inventory does not match registered phase seeds")
        if not isinstance(item.get("variant"), dict) or not isinstance(item["variant"].get("label"), str):
            raise ValueError("missing declared variant label")
        variant = item["variant"]
        labels = {row["id"] for row in plan["related_scan"]} | {"baseline_observed"}
        if variant["label"] not in labels or variant.get("binding_status") != "declared_not_runtime_verified" or variant.get("actual_parameters") is not None:
            raise ValueError("unsupported variant declaration")
        if item.get("status") != "preparation_only" or item.get("ready_to_select_parameters") is not False or item.get("parameter_acceptance") is not None:
            raise ValueError("inventory cannot claim parameter acceptance")
        if not isinstance(item.get("groups"), dict) or not isinstance(item.get("errors"), list) or type(item.get("seed_inventory_complete")) is not bool:
            raise ValueError("missing inventory quality fields")
        current_ids = _check_records(item)
        overlap = overlap or bool(run_ids.intersection(current_ids))
        run_ids.update(current_ids)
        cohorts.append(item)
    errors = []
    if overlap:
        errors.append("run_identity_overlap_between_cohorts")
    if len(cohorts) < 2:
        errors.append("fewer_than_two_distinct_cohorts")
    if len({item["phase"] for item in cohorts}) != 1:
        errors.append("phase_mismatch")
    if len({item["variant"]["label"] for item in cohorts}) != len(cohorts):
        errors.append("duplicate_variant_label")
    contexts = []
    configs = []
    for item in cohorts:
        if not item["seed_inventory_complete"] or item["errors"] or set(item["metadata_qualified_seeds"]) != set(item["expected_seeds"]):
            errors.append("incomplete_cohort:" + item["variant"]["label"])
        if len(item["groups"]) != 1:
            errors.append("mixed_cohort_dimensions")
            continue
        group = next(iter(item["groups"].values()))
        dimensions = group.get("dimensions") if isinstance(group, dict) else None
        if not isinstance(dimensions, dict) or any(not isinstance(dimensions.get(key), str) or dimensions[key] in ("", "unknown") for key in DIMENSIONS):
            raise ValueError("invalid cohort dimensions")
        if dimensions["rules_version"] != RULE_VERSION or dimensions["offer_version"] != OFFER_VERSION or dimensions["source"] != "bot":
            errors.append("unsupported_cohort_context")
        contexts.append({key: dimensions[key] for key in CONTEXT})
        configs.append(dimensions["config_hash"])
    if contexts and any(context != contexts[0] for context in contexts):
        errors.append("comparison_context_mismatch")
    if len(set(configs)) != len(configs):
        errors.append("same_configuration_for_distinct_labels")
    common = set.intersection(*(set(item["metadata_qualified_seeds"]) for item in cohorts)) if cohorts else set()
    return {"schema": "random-cohort-pairing-v1", "status": "preparation_only", "plan_sha256": plan_hash,
            "seed_pairing_complete": not errors, "shared_metadata_qualified_seeds": sorted(common, key=int),
            "cohorts": [{"phase": item["phase"], "variant": item["variant"], "missing_seeds": item.get("missing_seeds")} for item in cohorts],
            "errors": errors, "pending": pending + MISSING_EVIDENCE,
            "independent_parent_runs": None, "comparison_ready": False, "parameter_acceptance": None}
