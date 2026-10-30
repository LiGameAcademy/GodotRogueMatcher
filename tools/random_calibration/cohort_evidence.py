"""Link explicit batch inventories to existing run-summary sidecars, never raw telemetry."""

from __future__ import annotations

import json
from pathlib import Path
import re
from typing import Any

from calibration_plan import validate_plan
from cohort_inventory import validate_inventory
from report_preflight import MAX_TOTAL_BYTES, read_object

MAX_RUN_SUMMARIES = 10000
SUMMARY_FIELDS = {"source": "source", "rules_version": "rule_version", "strategy": "strategy_version",
                  "config_hash": "config_hash", "mode_id": "mode_id", "content_version": "content_version",
                  "offer_version": "offer_version", "build": "build_id", "bot_config_hash": "bot_config_hash"}
PENDING = ["summary_identity_is_not_raw_telemetry_verification", "pool_audit_coverage_not_verified",
           "runtime_parameter_binding_unverified", "independent_parent_lineage_unverified", "engine_build_not_in_run_summary"]


def _diagnostics(summary: dict[str, Any], record: dict[str, Any], dimensions: dict[str, str]) -> list[str]:
    issues: list[str] = []
    if summary.get("summary_version") != "run-summary-v2":
        issues.append("unsupported_run_summary_version")
    if summary.get("schema_version") != "2" or any(key in summary for key in ("segment_id", "resume", "resume_branches")):
        issues.append("unsupported_or_resume_telemetry_schema")
    if summary.get("seed") != record["seed"]:
        issues.append("seed_mismatch")
    for dimension, field in SUMMARY_FIELDS.items():
        if summary.get(field) != dimensions[dimension]:
            issues.append("dimension_mismatch:" + dimension)
    for field in ("status", "reason"):
        if summary.get(field) != record[field]:
            issues.append("endpoint_mismatch:" + field)
    if summary.get("record_complete") is not True or summary.get("data_integrity") != "complete":
        issues.append("incomplete_run_summary")
    if summary.get("status") != "completed" or summary.get("reason") not in ("board_full", "challenge_completed") or summary.get("end_class") != "gameplay_terminal":
        issues.append("not_natural_terminal")
    if summary.get("source") != "bot" or summary.get("initialization") != "normal" or summary.get("collection_context") != "bot_batch":
        issues.append("not_normal_bot_batch")
    if "parent_run_id" not in summary or summary["parent_run_id"] is not None:
        issues.append("missing_or_nonroot_parent_declaration")
    if record["issues"]:
        issues.append("inventory_record_has_quality_diagnostics")
    return issues


def verify(plan: dict[str, Any], plan_hash: str, inventory_path: Path, paths: list[Path]) -> dict[str, Any]:
    """Verify metadata identity/quality only; sidecars cannot establish experiment acceptance."""
    if not 1 <= len(paths) <= MAX_RUN_SUMMARIES:
        raise ValueError("provide 1 to 10000 explicit run-summary files")
    item, inventory_hash, total_bytes = read_object(inventory_path)
    expected_ids = validate_inventory(plan, plan_hash, item)
    records = {record["run_id"]: record for record in item["records"]}
    rows: dict[str, dict[str, Any]] = {}
    contents: dict[str, str] = {}
    for path in paths:
        summary, digest, size = read_object(path)
        total_bytes += size
        if total_bytes > MAX_TOTAL_BYTES:
            raise ValueError("inventory and run summaries exceed the 32 MiB budget")
        run_id = summary.get("run_id")
        if not isinstance(run_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,256}", run_id):
            raise ValueError("run summary lacks a valid run_id")
        canonical = json.dumps(summary, sort_keys=True, ensure_ascii=False, allow_nan=False)
        artifact = {"path": str(path.resolve()), "sha256": digest}
        if run_id in rows:
            if contents[run_id] != canonical:
                raise ValueError("conflicting run summaries for run_id: " + run_id)
            rows[run_id]["artifacts"].append(artifact)
            continue
        contents[run_id] = canonical
        issues = ["unplanned_run_id"]
        if run_id in records:
            record = records[run_id]
            dimensions = item["groups"][record["group"]]["dimensions"]
            issues = _diagnostics(summary, record, dimensions)
        rows[run_id] = {"run_id": run_id, "seed": summary.get("seed"), "issues": issues, "artifacts": [artifact]}
    observed_ids = set(rows)
    matched = sorted(run_id for run_id, row in rows.items() if not row["issues"])
    missing = sorted(expected_ids - observed_ids)
    extra = sorted(observed_ids - expected_ids)
    errors: list[str] = []
    if not item["seed_inventory_complete"]:
        errors.append("inventory_not_complete")
    if missing:
        errors.append("missing_run_summaries")
    if extra:
        errors.append("unplanned_run_summaries")
    if any(row["issues"] for row in rows.values()):
        errors.append("run_summary_diagnostics")
    return {"schema": "random-cohort-evidence-v1", "status": "preparation_only", "plan_sha256": plan_hash,
            "inventory": {"path": str(inventory_path.resolve()), "sha256": inventory_hash},
            "phase": item["phase"], "variant": item["variant"], "identity_link_complete": not errors,
            "matched_run_ids": matched, "missing_run_ids": missing, "extra_run_ids": extra,
            "runs": [rows[run_id] for run_id in sorted(rows)], "errors": errors,
            "pending": validate_plan(plan) + PENDING, "telemetry_coverage_verified": False,
            "independent_parent_runs": None, "ready_to_select_parameters": False, "parameter_acceptance": None}
