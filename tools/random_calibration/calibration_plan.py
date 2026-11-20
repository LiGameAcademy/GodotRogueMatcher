"""Register a staged random-parameter experiment without modifying game resources."""

from __future__ import annotations

import math
from typing import Any

MAX_SEED = (1 << 63) - 1
RULE_VERSION = "run-commands-v46-unified-offer-audit"
OFFER_VERSION = "offer-unified-trial-v2"
PLAN_SCHEMA = "random-calibration-plan-v1"
CRITERIA = ("minimum_meaningful_effect", "maximum_uncertainty", "maximum_runs", "stop_rule")


def seed_value(value: str) -> int:
    """Accept only the canonical nonnegative 63-bit master-seed representation."""
    if not isinstance(value, str) or not value.isascii() or not value.isdecimal():
        raise ValueError("seed must be a canonical decimal string")
    number = int(value)
    if str(number) != value or number > MAX_SEED:
        raise ValueError("seed outside canonical nonnegative 63-bit range")
    return number


def make_plan(first_seed: str, smoke: int = 3, explore: int = 100, confirm: int = 150) -> dict[str, Any]:
    start = seed_value(first_seed)
    counts = {"smoke": smoke, "explore": explore, "confirm": confirm}
    if any(type(count) is not int or not 1 <= count <= 10000 for count in counts.values()):
        raise ValueError("phase budgets must be integers from 1 to 10000")
    if start + sum(counts.values()) - 1 > MAX_SEED:
        raise ValueError("seed interval exceeds the 63-bit range")
    seeds: dict[str, list[str]] = {}
    for phase, count in counts.items():
        seeds[phase] = [str(number) for number in range(start, start + count)]
        start += count
    return {
        "schema": PLAN_SCHEMA,
        "status": "preparation_only",
        "rule_version": RULE_VERSION,
        "offer_version": OFFER_VERSION,
        "budget_status": "experimental_starting_budget_not_acceptance_threshold",
        "seeds": seeds,
        "seed_policy": "reuse within phase across variants; confirm only after candidate freeze",
        "related_scan": [{"id": f"a_{value}", "a": value, "d": 0.25} for value in [0.0, 0.25, 0.5]],
        "gap_scan": {"selected_a": None, "d_values": [0.0, 0.25, 0.5], "requires": "register selected_a after related scan review"},
        "criteria": dict.fromkeys(CRITERIA),
        "criterion_units": {"minimum_meaningful_effect": None, "maximum_uncertainty": None},
        "parameter_acceptance": None,
        "runner": {"path": "tools/bot_testing/batch_cli.gd", "parameter_override_supported": True},
    }


def validate_plan(plan: dict[str, Any]) -> list[str]:
    """Validate registration structure; return unresolved decisions, never select parameters."""
    if plan.get("schema") != PLAN_SCHEMA or plan.get("status") != "preparation_only":
        raise ValueError("unsupported plan schema or status")
    if plan.get("rule_version") != RULE_VERSION or plan.get("offer_version") != OFFER_VERSION:
        raise ValueError("unsupported rule or offer version")
    if plan.get("parameter_acceptance") is not None:
        raise ValueError("this tool cannot accept or write back parameters")
    phases = plan.get("seeds")
    if not isinstance(phases, dict) or set(phases) != {"smoke", "explore", "confirm"}:
        raise ValueError("missing phase seed lists")
    seen: set[int] = set()
    for phase in ("smoke", "explore", "confirm"):
        values = phases[phase]
        if not isinstance(values, list) or not 1 <= len(values) <= 10000:
            raise ValueError("invalid phase seed budget")
        parsed = [seed_value(value) for value in values]
        if len(set(parsed)) != len(parsed) or seen.intersection(parsed):
            raise ValueError("duplicate seed within or across phases")
        seen.update(parsed)
    scans = plan.get("related_scan")
    if not isinstance(scans, list) or len(scans) != 3:
        raise ValueError("related scan must register three variants")
    if any(not isinstance(row, dict) or any(type(row.get(key)) not in (int, float) for key in ("a", "d")) for row in scans):
        raise ValueError("scan coefficients must be numeric, not booleans")
    if scans != [{"id": f"a_{value}", "a": value, "d": 0.25} for value in [0.0, 0.25, 0.5]]:
        raise ValueError("unsupported related scan; no implicit cartesian product")
    gap = plan.get("gap_scan")
    if not isinstance(gap, dict) or gap.get("selected_a") is not None or gap.get("d_values") != [0.0, 0.25, 0.5] or any(type(value) not in (int, float) for value in gap["d_values"]):
        raise ValueError("gap scan selection is outside this preparation slice")
    criteria = plan.get("criteria")
    if not isinstance(criteria, dict) or set(criteria) != set(CRITERIA):
        raise ValueError("missing acceptance criteria registry")
    pending: list[str] = []
    for name in CRITERIA:
        value = criteria[name]
        if value is None:
            pending.append("unregistered_criterion:" + name)
        elif name == "stop_rule":
            if not isinstance(value, str) or not value.strip():
                raise ValueError("stop_rule must be nonempty text or null")
        elif name == "maximum_runs":
            if type(value) is not int or value <= 0:
                raise ValueError("maximum_runs must be a positive integer or null")
        elif type(value) not in (int, float) or value <= 0 or (type(value) is float and not math.isfinite(value)):
            raise ValueError("effect and uncertainty criteria must be finite positive numbers or null")
    units = plan.get("criterion_units")
    if not isinstance(units, dict):
        raise ValueError("criterion units registry is required")
    for name in ("minimum_meaningful_effect", "maximum_uncertainty"):
        if criteria[name] is not None and (not isinstance(units.get(name), str) or not units[name].strip()):
            raise ValueError("numeric criteria require explicit units")
    runner = plan.get("runner")
    if not isinstance(runner, dict) or set(runner) != {"path", "parameter_override_supported"} or runner.get("path") != "tools/bot_testing/batch_cli.gd" or type(runner.get("parameter_override_supported")) is not bool:
        raise ValueError("invalid runner capability declaration")
    execution = "runner_execution_not_performed" if runner["parameter_override_supported"] else "runner_parameter_injection_unavailable"
    return pending + [execution, "gap_scan_selection_pending", "seed_identity_and_variant_binding_not_in_summary"]
