"""Synthetic sidecar identity/quality cases, never actual experiment observations."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
from typing import Any
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "random_calibration"))
from cohort_evidence import verify
import test_cohort_inventory as cohort_helpers


class EvidenceTests(unittest.TestCase):
    # Reuse fixture/IO helpers without inheriting or discovering the old tests again.
    cleanup_directory = cohort_helpers.CohortTests.cleanup_directory
    write = cohort_helpers.CohortTests.write
    rows = cohort_helpers.CohortTests.rows
    batch = cohort_helpers.CohortTests.batch
    index = cohort_helpers.CohortTests.index
    cli = cohort_helpers.CohortTests.cli

    def setUp(self) -> None:
        cohort_helpers.CohortTests.setUp(self)
        self.item = self.index(self.rows())
        self.inventory_path = self.write("inventory.json", self.item)

    def summaries(self) -> list[dict[str, Any]]:
        dimensions = next(iter(self.item["groups"].values()))["dimensions"]
        return [{"summary_version": "run-summary-v2", "schema_version": "2", "run_id": row["run_id"],
                 "seed": row["seed"], "source": dimensions["source"], "rule_version": dimensions["rules_version"],
                 "strategy_version": dimensions["strategy"], "config_hash": dimensions["config_hash"],
                 "mode_id": dimensions["mode_id"], "content_version": dimensions["content_version"],
                 "offer_version": dimensions["offer_version"], "build_id": dimensions["build"],
                 "bot_config_hash": dimensions["bot_config_hash"], "status": "completed", "reason": "board_full",
                 "record_complete": True, "data_integrity": "complete", "end_class": "gameplay_terminal",
                 "initialization": "normal", "collection_context": "bot_batch", "parent_run_id": None,
                 "fixture_note": "synthetic contract input, not gameplay evidence"} for row in self.item["records"]]

    def sidecars(self, summaries: list[dict[str, Any]] | None = None) -> list[Path]:
        return [self.write(f"summary-{index}.json", value) for index, value in enumerate(self.summaries() if summaries is None else summaries)]

    def test_complete_identity_link_keeps_all_experiment_claims_unverified(self) -> None:
        result = verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars())
        self.assertTrue(result["identity_link_complete"])
        self.assertEqual(len(result["matched_run_ids"]), 3)
        self.assertFalse(result["telemetry_coverage_verified"])
        self.assertFalse(result["ready_to_select_parameters"])
        self.assertIsNone(result["independent_parent_runs"])
        self.assertIsNone(result["variant"]["actual_parameters"])
        self.assertIsNone(result["parameter_acceptance"])

    def test_missing_and_unrelated_run_summaries_are_not_substituted(self) -> None:
        summaries = self.summaries()
        summaries[0]["run_id"] = "unrelated-run"
        result = verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars(summaries))
        self.assertFalse(result["identity_link_complete"])
        self.assertEqual(result["extra_run_ids"], ["unrelated-run"])
        self.assertEqual(result["missing_run_ids"], [self.item["records"][0]["run_id"]])
        self.assertEqual(len(result["runs"]), 3)

    def test_seed_and_all_group_dimensions_must_match(self) -> None:
        for field in ("seed", "source", "rule_version", "strategy_version", "config_hash", "mode_id",
                      "content_version", "offer_version", "build_id", "bot_config_hash", "status", "reason"):
            summaries = self.summaries()
            summaries[0][field] = "other"
            result = verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars(summaries))
            with self.subTest(field=field):
                self.assertFalse(result["identity_link_complete"])
                self.assertTrue(result["runs"][0]["issues"])

    def test_missing_quality_fixture_recovered_and_resume_are_visible(self) -> None:
        for field, value in [("summary_version", "recovered-run-summary-v2"), ("schema_version", "3"),
                             ("record_complete", "true"), ("data_integrity", "prefix_only"),
                             ("end_class", "tool_censored"), ("initialization", "fixture_f6"),
                             ("collection_context", "fixture"), ("parent_run_id", "parent"),
                             ("resume_branches", []), ("segment_id", None), ("resume", {})]:
            summaries = self.summaries()
            summaries[0][field] = value
            with self.subTest(field=field):
                result = verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars(summaries))
                self.assertFalse(result["identity_link_complete"])
        summaries = self.summaries()
        del summaries[0]["parent_run_id"]
        self.assertFalse(verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars(summaries))["identity_link_complete"])

    def test_same_run_content_aliases_but_conflicts_do_not_choose_a_winner(self) -> None:
        paths = self.sidecars()
        alias = self.write("alias.json", self.summaries()[0])
        alias.write_text(json.dumps(self.summaries()[0], indent=2, sort_keys=True), encoding="utf-8")
        paths.append(alias)
        result = verify(self.plan, self.plan_hash, self.inventory_path, paths)
        self.assertTrue(result["identity_link_complete"])
        self.assertEqual(len(result["runs"]), 3)
        self.assertEqual(len(result["runs"][0]["artifacts"]), 2)
        changed = self.summaries()[0]
        changed["fixture_note"] = "changed export"
        paths.append(self.write("conflict.json", changed))
        with self.assertRaisesRegex(ValueError, "conflicting run summaries"):
            verify(self.plan, self.plan_hash, self.inventory_path, paths)

    def test_incomplete_inventory_cannot_be_upgraded_by_complete_sidecars(self) -> None:
        rows = self.rows()
        rows[0]["replay_error"] = "synthetic mismatch"
        item = self.index(rows)
        self.write("inventory.json", item)
        result = verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars())
        self.assertFalse(result["identity_link_complete"])
        self.assertIn("inventory_not_complete", result["errors"])

    def test_invalid_inventory_and_limits_fail_before_linking(self) -> None:
        paths = self.sidecars()
        for mutate in [lambda p: p.__setitem__("plan_sha256", "wrong"),
                       lambda p: p["metadata_qualified_seeds"].append("9999"),
                       lambda p: next(iter(p["groups"].values()))["dimensions"].__setitem__("rules_version", "old")]:
            item = copy.deepcopy(self.item)
            mutate(item)
            self.write("inventory.json", item)
            with self.assertRaises(ValueError):
                verify(self.plan, self.plan_hash, self.inventory_path, paths)
        self.write("inventory.json", self.item)
        with self.assertRaises(ValueError):
            verify(self.plan, self.plan_hash, self.inventory_path, [])
        with patch("cohort_evidence.MAX_TOTAL_BYTES", 8), self.assertRaises(ValueError):
            verify(self.plan, self.plan_hash, self.inventory_path, paths)
        with patch("cohort_evidence.MAX_RUN_SUMMARIES", 2), self.assertRaises(ValueError):
            verify(self.plan, self.plan_hash, self.inventory_path, paths)

    def test_embedded_paths_are_never_followed(self) -> None:
        item = copy.deepcopy(self.item)
        item["source"]["path"] = "does-not-exist/input.csv"
        item["records"][0]["record_path"] = "does-not-exist/record.jsonl"
        self.write("inventory.json", item)
        result = verify(self.plan, self.plan_hash, self.inventory_path, self.sidecars())
        self.assertTrue(result["identity_link_complete"])

    def test_actual_verify_cli_exits_and_preserves_inputs_outputs(self) -> None:
        paths = self.sidecars()
        originals = [path.read_bytes() for path in paths]
        output = self.directory / "linked.json"
        args = ["verify", str(self.plan_path), str(self.inventory_path), *(str(path) for path in paths), "--output", str(output)]
        result = self.cli(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        original_output = output.read_bytes()
        self.assertEqual(self.cli(*args).returncode, 2)
        self.assertEqual(output.read_bytes(), original_output)
        self.assertEqual([path.read_bytes() for path in paths], originals)
        summaries = self.summaries()
        summaries[0]["schema_version"] = "3"
        self.sidecars(summaries)
        args[-1] = str(self.directory / "blocked.json")
        self.assertEqual(self.cli(*args).returncode, 1)
        paths[0].write_text('{"run_id":"x","run_id":"x"}', encoding="utf-8")
        args[-1] = str(self.directory / "bad.json")
        result = self.cli(*args)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)

    def test_incomplete_record_missing_or_invalid_endpoint_fails_without_traceback(self) -> None:
        rows = self.rows()
        rows[0]["replay_error"] = "synthetic mismatch"
        incomplete = self.index(rows)
        paths = self.sidecars()
        for field in ("status", "reason"):
            for index, invalid in enumerate((None, [], 1)):
                item = copy.deepcopy(incomplete)
                if invalid is None:
                    del item["records"][0][field]
                else:
                    item["records"][0][field] = invalid
                self.write("inventory.json", item)
                result = self.cli("verify", str(self.plan_path), str(self.inventory_path), *(str(path) for path in paths),
                                  "--output", str(self.directory / f"malformed-{field}-{index}.json"))
                with self.subTest(field=field, invalid=invalid):
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
