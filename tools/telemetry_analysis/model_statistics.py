"""Descriptive observations with explicit denominators and run-cluster intervals."""
from __future__ import annotations

import math
import random
from collections import defaultdict
from typing import Any

from import_sources import Json, digest

VERSION = "model-analysis-v1"
HUMAN_CONTEXTS = {"editor_playtest", "web_playtest"}
DIMENSIONS = ("mode_id", "source", "collection_context", "initialization", "schema_version",
              "rule_version", "content_version", "offer_version", "build_id", "commit_id",
              "config_hash", "pressure_version", "collection_config_hash", "strategy_version",
              "bot_config_hash", "experiment_id", "variant_id")


def quantile(values: list[float], q: float) -> float | None:
    return sorted(values)[math.floor(q * (len(values) - 1))] if values else None


def number(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def wilson(n: float, d: int) -> list[float] | None:
    if not d:
        return None
    z = 1.959963984540054
    p = n / d
    center = (p + z * z / (2 * d)) / (1 + z * z / d)
    spread = z * math.sqrt(p * (1 - p) / d + z * z / (4 * d * d)) / (1 + z * z / d)
    return [max(0, center - spread), min(1, center + spread)]


class Metrics:
    def __init__(self, dimensions: Json, seed: int = 17002, repetitions: int = 500) -> None:
        self.dimensions = dimensions
        self.group_hash = digest(dimensions)
        self.seed = seed
        self.repetitions = repetitions
        self.rows: dict[str, Json] = {}
        self.clusters: dict[str, str] = {}

    def add(self, metric: str, unit: str, event: Json, value: float | None,
            scope: Json | None = None, method: str = "mean", missing: str = "") -> None:
        scope = scope or {}
        key = digest([metric, scope])
        if key not in self.rows:
            self.rows[key] = {"metric_id": metric, "unit": unit, "group_hash": self.group_hash,
                              "dimensions": self.dimensions, "skill_id": None, "level": None,
                              "H": None, **scope, "method": method, "samples": [],
                              "missing_refs": [], "missing_reasons": []}
        row = self.rows[key]
        if value is None:
            row["missing_refs"].append(event["event_id"])
            if missing and missing not in row["missing_reasons"]:
                row["missing_reasons"].append(missing)
        else:
            seed = event.get("seed")
            self.clusters[event["run_id"]] = ("seed:" + seed if self.dimensions.get("source") == "bot"
                                              and isinstance(seed,str) and seed != "unknown" else event["run_id"])
            row["samples"].append((event["run_id"], event["event_id"], value))

    def finish(self, min_runs: int, min_events: int) -> list[Json]:
        result: list[Json] = []
        for row in self.rows.values():
            samples = row.pop("samples")
            clusters: dict[str, list[float]] = defaultdict(list)
            for run, _, value in samples:
                clusters[self.clusters[run]].append(value)
            unique_runs = len({run for run,_,_ in samples})
            values = [value for _, _, value in samples]
            d = len(values)
            n = sum(values)
            row.update({"numerator": n if d else None, "denominator": d, "n_events": d,
                        "n_runs": unique_runs, "n_clusters":len(clusters),
                        "value": (n if row["method"] == "count" else n / d) if d else None,
                        "p10": quantile(values, .1), "p50": quantile(values, .5),
                        "p90": quantile(values, .9), "missing": len(row["missing_refs"]),
                        "source_refs": [event for _, event, _ in samples],
                        "analyzer_version": VERSION, "quantile_method": "floor(q*(n-1))",
                        "ci95": None, "bootstrap_seed": self.seed,
                        "bootstrap_repetitions": self.repetitions})
            if row["method"] == "proportion":
                row["wilson95"] = wilson(n, d)
                row["wilson_caveat"] = "描述区间；同局事件相关，不能当作独立玩家"
            # Run-cluster bootstrap, rather than treating every action as independent.
            if len(clusters) >= 2 and self.repetitions and row["method"] != "count":
                rng = random.Random(self.seed)
                pools = list(clusters.values())
                estimates: list[float] = []
                for _ in range(self.repetitions):
                    draw = [v for pool in rng.choices(pools, k=len(pools)) for v in pool]
                    estimates.append(sum(draw) / len(draw))
                row["ci95"] = [quantile(estimates, .025), quantile(estimates, .975)]
            context = self.dimensions.get("collection_context")
            unknown = context in (None, "unknown") or self.dimensions.get("schema_version") != "2"
            row["quality"] = ("no_opportunity" if not d else
                              "dataset_diagnostics_require_review" if self.dimensions.get("observation_integrity") == "rule_error_prefix" else
                              "unknown_context" if unknown else
                              "insufficient_samples" if len(clusters) < min_runs or d < min_events else
                              "candidate")
            result.append(row)
        return sorted(result, key=lambda r: (r["metric_id"], r.get("stage_id") or 0,
                                            r["skill_id"] or "", r["level"] or 0, digest(r)))


def analyze(events: list[Json], min_runs: int = 30, min_events: int = 100,
            seed: int = 17002, repetitions: int = 500) -> Json:
    runs: dict[str, list[Json]] = defaultdict(list)
    for event in events:
        runs[event["run_id"]].append(event)
    groups: dict[str, Metrics] = {}
    run_rows: list[Json] = []
    exits: list[Json] = []
    runtime_configs: list[Json] = []
    for run, rows in sorted(runs.items()):
        rows.sort(key=lambda e: int(e["telemetry_seq"]))
        header = rows[0]
        dimensions = {key: header.get(key, "unknown") for key in DIMENSIONS}
        final = rows[-1]
        terminal = final["event_name"] == "run_ended"
        ending = final["payload"] if terminal else {}
        status = ending.get("status", "incomplete")
        dimensions["observation_integrity"] = "rule_error_prefix" if status == "rule_error" else "validated_stream"
        group_hash = digest(dimensions)
        metric = groups.setdefault(group_hash, Metrics(dimensions, seed, repetitions))
        complete = terminal and ending.get("record_complete") is True
        runtime_configs.append({"run_id":run,"group_hash":group_hash,
                                "config":header["payload"].get("config",{}),
                                "source_ref":header["event_id"]})
        run_rows.append({"run_id": run, "group_hash": group_hash, "status": status,
                         "reason": ending.get("reason", "missing_ending"), "complete": complete,
                         "score": ending.get("score"), "dimensions": dimensions})
        generated: dict[str, Json] = {}
        presented: set[str] = set()
        acquired: dict[str, Json] = {}
        reached: dict[int, Json] = {}
        passed: dict[int, Json] = {}
        installed: dict[tuple[str, int], Json] = {}
        observation: Json = header["payload"].get("initial_observation", {})
        eligible_actions = 0
        for event in rows:
            name, payload = event["event_name"], event["payload"]
            if name in {"ui_observed", "observation_checkpoint"}:
                observation = payload
            stage = payload.get("stage_before", payload.get("stage", {}))
            stage_id = int(stage["stage_id"]) if stage.get("stage_id") else None
            if stage_id is not None:
                reached.setdefault(stage_id, event)
            scope: Json = {"stage_id": stage_id}
            if name == "offer_generated":
                generated[str(payload["offer_id"])] = event
                pressure = number(payload.get("P_offer", {}).get("P"))
                metric.add("pressure_offer", "pressure", event, pressure, scope)
            elif name == "offer_presented":
                presented.add(str(payload["offer_id"]))
            elif name == "skill_acquired":
                acquired[str(payload["offer_id"])] = event
                level = int(payload["count_after"])
                skill_scope = {"skill_id": payload["skill_id"], "level": level}
                installed[(payload["skill_id"], level)] = event
                for key, field, unit in (("choice_score", "score_delta", "points/choice"),
                                         ("choice_net_space", "net_empty", "cells/choice")):
                    metric.add(key, unit, event, number(payload[field]), skill_scope)
            elif name == "action_resolved":
                entities_valid = (len(set(payload["created_ids"])) == int(payload["created"]) and
                                  len(set(payload["removed_ids"])) == int(payload["removed"]))
                ledger_valid = (sum(int(entry["final_score"]) for entry in payload["ledger_entries"]) ==
                                int(payload["action_score_delta"]))
                if not payload["complete"] or not payload.get("space_consistent") or not entities_valid or not ledger_valid:
                    metric.add("action_score", "points/action", event, None, scope,
                               missing="incomplete_action_or_space_mismatch")
                    continue
                eligible_actions += 1
                action_scope = {**scope, "action_type": payload.get("action_type", "unknown"),
                                "build_hash": digest(payload.get("build_before", {})),
                                "pressure_band": int(float(payload["P_before"]["P"]) // 20) * 20}
                for key, field, unit in (("action_score", "action_score_delta", "points/action"),
                                         ("born", "created", "pieces/action"),
                                         ("removed", "removed", "pieces/action"),
                                         ("q_frozen", "q_frozen", "pieces/batch")):
                    metric.add(key, unit, event, number(payload[field]), action_scope)
                metric.add("net_space", "cells/action", event,
                           int(payload["removed"]) - int(payload["created"]), action_scope)
                for side in ("before", "after"):
                    metric.add("pressure_" + side, "pressure", event,
                               number(payload["P_" + side]["P"]), action_scope)
                metric.add("p_direct", "probability", event, None, action_scope,
                           method="proportion", missing="match_phase_not_recorded")
                metric.add("p_allclear", "probability", event, None, action_scope,
                           method="proportion", missing="pre_refill_empty_not_recorded")
                for skill, raw_level in payload.get("build_before", {}).items():
                    if int(raw_level) <= 0:
                        continue
                    skill_scope = {**scope, "skill_id": skill, "level": int(raw_level)}
                    metric.add("skill_action_exposure", "actions", event, 1, skill_scope, method="count")
                    metric.add("skill_trigger_rate", "triggers/action", event, None, skill_scope,
                               missing="ability_attempts_not_recorded")
            elif name == "stage_goal_completed":
                result = payload["result"]
                identifier = int(event.get("stage_id") or result["stage_id"])
                passed.setdefault(identifier, event)
                reached.setdefault(identifier, event)
                goal_scope = {"stage_id": identifier}
                for key, field, unit in (("goal_actions", "used_actions", "actions/goal"),
                                         ("goal_carry", "carry_out", "points/goal")):
                    metric.add(key, unit, event, number(result.get(field)), goal_scope,
                               missing="missing_goal_field")
            elif name == "observation_interval_closed":
                # Only known real-play context can represent human experience.
                if dimensions["source"] == "human" and dimensions["collection_context"] in HUMAN_CONTEXTS:
                    metric.add("interval_" + payload["category"], "ms/interval", event,
                               number(payload["duration_ms"]))
        for identifier, event in reached.items():
            if identifier in passed:
                value: float | None = 1
            elif complete and status == "completed":
                value = 0
            else:
                value = None  # Abandoned/censored/active is not gameplay failure.
            metric.add("stage_completion", "probability", event, value,
                       {"stage_id": identifier}, "proportion", "stopped_before_resolution")
        for offer_id, event in generated.items():
            payload = event["payload"]
            opportunity = dimensions["source"] == "bot" or offer_id in presented
            if dimensions["source"] == "human" and dimensions["collection_context"] not in HUMAN_CONTEXTS:
                opportunity = False
            for skill in set(payload["choices"]):
                level = int(payload.get("levels", {}).get(skill, "0")) + 1
                picked = acquired.get(offer_id, {}).get("payload", {}).get("skill_id") == skill
                metric.add("selection_rate", "probability", event,
                           float(picked) if opportunity else None,
                           {"skill_id": skill, "level": level}, "proportion", "not_presented")
            metric.add("unshown_offer", "probability", event,
                       float(offer_id not in presented) if dimensions["source"] == "human" else None,
                       method="proportion", missing="not_human")
        for (skill, level), event in installed.items():
            metric.add("paired_score", "points/window", event, None,
                       {"skill_id": skill, "level": level, "H": None},
                       missing="no_legal_counterfactual_window")
            metric.add("paired_space", "cells/window", event, None,
                       {"skill_id": skill, "level": level, "H": None},
                       missing="no_legal_counterfactual_window")
        known = {r["skill_id"] for r in metric.rows.values() if r["skill_id"] is not None}
        for definition in header["payload"].get("config",{}).get("skills",[]):
            skill = definition.get("skill_id")
            if skill and skill not in known:
                metric.add("selection_rate", "probability", header, None,
                           {"skill_id":skill,"level":1}, "proportion", "no_recorded_offer_opportunity")
        if terminal:
            observation = ending.get("last_observation", observation)
        exits.append({"run_id": run, "group_hash": group_hash, "status": status,
                      "end_class": {"completed":"gameplay_terminal", "abandoned":"user_stop",
                                    "censored":"tool_censored", "rule_error":"error"}.get(status,"not_ended"),
                      "reason": ending.get("reason", "unknown"), "complete": complete,
                      "ui": observation.get("ui", "unknown"),
                      "stage_id": observation.get("stage", {}).get("stage_id"),
                      "root_complete": observation.get("root_complete"),
                      "since_input_ms": observation.get("since_input_ms"),
                      "source_ref": final["event_id"], "complete_actions": eligible_actions})
    metrics = [row for group in groups.values() for row in group.finish(min_runs, min_events)]
    return {"analyzer_version": VERSION, "groups": {key: value.dimensions for key, value in groups.items()},
            "metrics": metrics, "runs": run_rows, "exits": exits, "runtime_configs":runtime_configs,
            "thresholds": {"min_runs": min_runs, "min_events": min_events,
                           "status": "engineering_trial_not_statistical_proof"}}
