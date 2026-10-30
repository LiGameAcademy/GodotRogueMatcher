"""Inspect existing analysis summaries only; never parse telemetry or merge overlapping datasets."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

from calibration_plan import OFFER_VERSION, RULE_VERSION, validate_plan

MAX_ARTIFACT_BYTES = 8 * 1024 * 1024
MAX_ARTIFACTS = 64
MAX_TOTAL_BYTES = 32 * 1024 * 1024


def _unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def _nonfinite(value: str) -> None:
    raise ValueError("nonfinite JSON number: " + value)


def _finite_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("nonfinite JSON number: " + value)
    return number


def read_object(path: Path) -> tuple[dict[str, Any], str, int]:
    with path.open("rb") as source:
        data = source.read(MAX_ARTIFACT_BYTES + 1)
    if len(data) > MAX_ARTIFACT_BYTES:
        raise ValueError("analysis artifact grew beyond the byte limit")
    value = json.loads(data.decode("utf-8-sig"), object_pairs_hook=_unique, parse_constant=_nonfinite, parse_float=_finite_float)
    if not isinstance(value, dict):
        raise ValueError("expected a JSON object: " + str(path))
    return value, hashlib.sha256(data).hexdigest(), len(data)


def inspect_summary(summary: dict[str, Any]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    pending: list[str] = []
    if summary.get("schema") != "telemetry-report-v1":
        errors.append("unsupported_analysis_schema")
    if not isinstance(summary.get("errors"), list) or summary["errors"]:
        errors.append("analysis_has_errors_or_unknown_quality")
    if type(summary.get("runs")) is not int or summary["runs"] <= 0:
        errors.append("no_run_observations")
    if type(summary.get("events")) is not int or summary["events"] <= 0:
        errors.append("no_event_observations")
    if "resume_branches" in summary:
        errors.append("resume_schema_3_not_supported_for_calibration")
    bounded = summary.get("bounded")
    if bounded is not None and (not isinstance(bounded, dict) or bounded.get("complete") is not True):
        errors.append("bounded_analysis_incomplete")
    groups = summary.get("groups")
    count = 0
    if not isinstance(groups, dict) or not groups:
        errors.append("missing_groups")
        groups = {}
    for key, group in groups.items():
        if not isinstance(group, dict) or type(group.get("count")) is not int or group["count"] <= 0:
            errors.append("invalid_group:" + key)
            continue
        count += group["count"]
        dimensions = group.get("dimensions")
        if not isinstance(dimensions, dict):
            errors.append("missing_dimensions:" + key)
            continue
        if dimensions.get("schema_version") != "2":
            errors.append("unsupported_telemetry_schema:" + key)
        if dimensions.get("rule_version") != RULE_VERSION or dimensions.get("offer_version") != OFFER_VERSION:
            errors.append("unsupported_rules_or_offer:" + key)
        for name in ("content_version", "config_hash", "strategy_version", "bot_config_hash", "mode_id", "commit_id"):
            if not isinstance(dimensions.get(name), str) or dimensions[name] in ("", "unknown"):
                errors.append("missing_dimension:" + key + ":" + name)
        if dimensions.get("source") != "bot" or dimensions.get("initialization") != "normal":
            pending.append("non_natural_bot_group:" + key)
        if group.get("status") != "completed":
            pending.append("censored_or_nonterminal_group:" + key)
    if count != summary.get("runs"):
        errors.append("group_run_count_mismatch")
    opportunities = summary.get("opportunities")
    if not isinstance(opportunities, dict):
        errors.append("missing_opportunity_coverage")
    else:
        if opportunities.get("opportunity_protocol") != "parent-run-reward-v1":
            errors.append("unsupported_opportunity_protocol")
        coverage = opportunities.get("pool_audit")
        if not isinstance(coverage, dict) or type(coverage.get("complete_rewards")) is not int or type(coverage.get("legacy_rewards")) is not int or type(coverage.get("complete_rate")) not in (int, float):
            errors.append("missing_complete_pool_coverage")
        elif coverage["complete_rewards"] <= 0 or coverage.get("legacy_rewards") != 0 or coverage.get("complete_rate") != 1.0:
            errors.append("incomplete_or_empty_pool_coverage")
    return errors, pending


def audit(plan: dict[str, Any], paths: list[Path]) -> dict[str, Any]:
    pending = validate_plan(plan)
    if not 1 <= len(paths) <= MAX_ARTIFACTS:
        raise ValueError("provide 1 to 64 analysis summaries")
    artifacts: list[dict[str, Any]] = []
    seen: dict[str, dict[str, Any]] = {}
    total_bytes = 0
    for path in paths:
        summary, digest, size = read_object(path)
        total_bytes += size
        if total_bytes > MAX_TOTAL_BYTES:
            raise ValueError("analysis summaries exceed the 32 MiB total input budget")
        if digest in seen:
            seen[digest]["aliases"].append(str(path.resolve()))
            continue
        errors, gaps = inspect_summary(summary)
        row = {"path": str(path.resolve()), "sha256": digest, "bytes": size, "aliases": [],
               "status": "rejected" if errors else "summary_preflight_valid",
               "errors": errors, "pending": gaps, "reported_runs": summary.get("runs"),
               "reported_events": summary.get("events"), "independent_parent_runs": None,
               "groups": summary.get("groups"), "pool_audit": summary.get("opportunities", {}).get("pool_audit") if isinstance(summary.get("opportunities"), dict) else None}
        artifacts.append(row)
        seen[digest] = row
    return {"schema": "random-calibration-preflight-v1", "status": "preparation_only",
            "summary_preflight_valid": all(not row["errors"] for row in artifacts),
            "ready_to_select_parameters": False, "parameter_acceptance": None,
            "pending": pending + ["first_engine_and_synergy_wait_not_in_summary", "natural_failure_vs_goal_split_not_in_summary", "high_k_coverage_not_in_summary", "cross_artifact_overlap_unknown_no_totals"],
            "artifacts": artifacts}
