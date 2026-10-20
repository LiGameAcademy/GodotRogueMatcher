"""Behavioral regression for offline calibration gates and curve boundaries."""
from __future__ import annotations

import copy
import unittest
from fractions import Fraction
from typing import Any

from import_sources import digest
from target_curve import (FINGERPRINTS, analyze, generate_targets, reference_actions,
                          resource_text, validate_profile, verified_runs)


def profile() -> dict[str, Any]:
    return {"profile_id": "test-normal-pool", "curve_version": "candidate-v1",
            "selection": {key: key + "-v1" for key in FINGERPRINTS},
            "bot_config": {"move_limit": "80"},
            "fallback_targets": [100, 150], "pressure_intervals": [4, 4],
            "min_seeds": 30, "min_actions": 100, "difficulty": 1, "rounding_step": 5}


def events(seeds: int = 30, points: int = 51) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for seed in range(seeds):
        run = f"run-{seed}"
        base = dict(profile()["selection"], schema_version="2", source="bot", initialization="normal",
                    collection_context="bot_batch", mode_id="stage_challenge", run_id=run, seed=str(seed),
                    experiment_id=None, parent_run_id=None)
        for stage in (1, 2):
            for action in range(4):
                index = (stage - 1) * 4 + action + 1
                payload = {"complete": True, "stage_before": {"enabled": True, "stage_id": str(stage)},
                           "created": "3", "removed": "5", "occupied_before": "15", "occupied_after": "13",
                           "space_consistent": True, "build_before": {"score_multiplier": stage - 1},
                           "ledger_entries": [{"final_score": str(points), "action_id": str(index), "reason": "match"},
                                              {"final_score": "9999", "action_id": "-1", "reason": "match"},
                                              {"final_score": "25", "action_id": str(index), "reason": "goal_bonus"}]}
                result.append(dict(base, event_name="action_resolved", event_id=f"{run}:{index}",
                                   telemetry_seq=str(index), root_action_id=str(index), payload=payload))
        result.append(dict(base, event_name="stage_goal_completed", event_id=f"{run}:9", telemetry_seq="9",
                           payload={"result": {"stage_id": "1", "used_actions": "4"}}))
        status, reason = ("completed", "board_full") if seed % 3 == 0 else ("censored", "move_limit") if seed % 3 == 1 else ("abandoned", "menu")
        result.append(dict(base, event_name="run_ended", event_id=f"{run}:10", telemetry_seq="10",
                           payload={"status": status, "reason": reason}))
    return result


class TargetCurveTests(unittest.TestCase):
    def analyze(self, source: list[dict[str, Any]] | None = None,
                config: dict[str, Any] | None = None) -> dict[str, Any]:
        source = events() if source is None else source
        return analyze(source, config or profile(), {e["run_id"] for e in source})

    def test_no_overlap_and_smoothing_boundaries(self) -> None:
        stages = (1, 3, 4, 5, 10, 11, 12, 13)
        self.assertEqual([reference_actions(s, False) for s in stages], [3, 3, 5, 5, 5, 10, 10, 10])
        self.assertEqual([reference_actions(s) for s in stages], [3, 3, 4, 5, 5, 7, 9, 10])
        for invalid in (0, -1, True, 1.5):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                reference_actions(invalid)

    def test_decimal_rounding_difficulty_and_missing_zero_are_distinct(self) -> None:
        self.assertEqual(generate_targets([50, 50.01], 1, 5), [150, 155])
        self.assertEqual(generate_targets([50], 1.5, 5), [225])
        self.assertEqual(generate_targets([Fraction(5, 3)], 1, 5), [5])
        self.assertEqual(generate_targets([0], 1, 5), [0])
        self.assertIsNone(generate_targets([None], 1, 5))
        for mean in (-1, True, "NaN", "Infinity", "text", 2**63):
            with self.subTest(mean=mean), self.assertRaises(ValueError):
                generate_targets([mean], 1, 5)
        for scale, step in ((0, 5), (-1, 5), (1, 0), (1, 1.1), (True, 5), ("NaN", 5)):
            with self.subTest(scale=scale, step=step), self.assertRaises(ValueError):
                generate_targets([50], scale, step)

    def test_full_actions_include_zero_and_space_not_score_multiplier(self) -> None:
        report = self.analyze()
        self.assertEqual(report["candidate_targets"], [155, 155])
        self.assertEqual(report["target_policy"], "offline_reference")
        self.assertEqual(report["stages"][0]["mu_reference_observed"], 51)
        self.assertEqual(report["stages"][0]["space_drift_observed"], -2)
        self.assertEqual(report["stages"][0]["complete_actions"], 120)
        self.assertEqual(report["stages"][1]["endings"], {"board_full_unmet": 10, "tool_censored": 10, "abandoned": 10})
        self.assertEqual(report["stages"][1]["observed_reached"], 30)
        self.assertEqual(report["stages"][0]["passed_actions_p50_p90"], [4, 4])
        self.assertIsNone(report["stages"][1]["passed_actions_p50_p90"][0])
        self.assertEqual(report["stages"][0]["within_reference_actions_rate_known"], 0)
        text = resource_text(report)
        self.assertIn('target_policy = "offline_reference"', text)
        self.assertIn('targets = Array[int]([155, 155])', text)

    def test_no_late_stage_coverage_keeps_entire_old_curve(self) -> None:
        config = profile()
        config["fallback_targets"].append(200)
        config["pressure_intervals"].append(4)
        report = self.analyze(config=config)
        self.assertIsNone(report["candidate_targets"])
        self.assertEqual(report["exported_targets"], [100, 150, 200])
        self.assertIsNone(report["stages"][2]["mu_reference_observed"])
        self.assertEqual(report["stages"][2]["complete_actions"], 0)

    def test_measured_zero_is_recorded_but_does_not_export_invalid_goal(self) -> None:
        report = self.analyze(events(points=0))
        self.assertEqual(report["candidate_targets"], [0, 0])
        self.assertEqual(report["reason"], "zero_score_reference")
        self.assertEqual(report["exported_targets"], [100, 150])

    def test_no_replay_no_events_and_low_coverage_keep_fallback(self) -> None:
        for source in ([], events(3)):
            report = self.analyze(source)
            self.assertEqual(report["exported_targets"], [100, 150])
        report = analyze(events(), profile(), set())
        self.assertEqual(report["excluded_events"]["missing_exact_replay"], 300)
        self.assertEqual(report["exported_targets"], [100, 150])

    def test_seed_clusters_not_run_count_and_partial_actions_excluded(self) -> None:
        source = events()
        for event in source:
            event["seed"] = "one-seed"
        source[0]["payload"]["complete"] = False
        report = self.analyze(source)
        self.assertEqual(report["stages"][0]["complete_actions"], 119)
        self.assertEqual(report["stages"][0]["independent_seeds"], 1)
        self.assertEqual(report["target_policy"], "fixed_fallback")

    def test_fixture_and_other_fingerprints_cannot_enter_reference(self) -> None:
        for key, value in (("source", "human"), ("collection_context", "fixture"),
                           ("experiment_id", "paired"), ("parent_run_id", "parent"),
                           ("config_hash", "other"), ("strategy_version", "other")):
            source = events()
            for event in source:
                event[key] = value
            with self.subTest(key=key):
                self.assertEqual(self.analyze(source)["target_policy"], "fixed_fallback")

    def test_dedup_and_conflicting_actions(self) -> None:
        source = events()
        report = self.analyze(source + copy.deepcopy(source))
        self.assertEqual(report["stages"][0]["complete_actions"], 120)
        extra = copy.deepcopy(source[0])
        extra["payload"]["created"] = "4"
        with self.assertRaisesRegex(ValueError, "conflicting duplicate"):
            self.analyze(source + [extra])
        extra["event_id"] = "other-event"
        with self.assertRaisesRegex(ValueError, "duplicate complete action"):
            self.analyze(source + [extra])

    def test_bad_space_and_missing_fingerprint_fail(self) -> None:
        source = events()
        source[0]["payload"]["occupied_after"] = "14"
        with self.assertRaisesRegex(ValueError, "space accounting"):
            self.analyze(source)
        for change in ({"min_seeds": 29}, {"min_actions": 99}, {"rounding_step": 0}, {"difficulty": 0}):
            config = profile() | change
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_profile(config)

    def test_replay_report_requires_matching_group_and_no_errors(self) -> None:
        config = profile()
        bot = {"move_limit": "80"}
        config["selection"]["bot_config_hash"] = digest(bot)
        selected = config["selection"]
        group = {"mode": "stage_challenge", "config_hash": selected["config_hash"],
                 "rules_version": selected["rule_version"], "strategy": selected["strategy_version"],
                 "bot_config": bot, "commit_id": selected["commit_id"], "errors": [],
                 "runs": [{"run_id": "good", "status": "completed"}, {"run_id": "bad", "status": "rule_error"}]}
        report = {"protocol": "pressure-batch-v1", "groups": {"one": group}}
        self.assertEqual(verified_runs(report, config), {"good"})
        group["errors"] = ["mismatch"]
        self.assertEqual(verified_runs(report, config), set())
        group["errors"] = []
        group["commit_id"] = "different"
        self.assertEqual(verified_runs(report, config), set())


if __name__ == "__main__":
    unittest.main()
