"""Synthetic batch-index contracts; these rows are not gameplay evidence."""

from __future__ import annotations

import copy
import csv
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "random_calibration"
sys.path.insert(0, str(TOOL))
from calibration_plan import OFFER_VERSION, RULE_VERSION, make_plan
from cohort_inventory import inventory, compare
from report_preflight import read_object


class CohortTests(unittest.TestCase):
    def setUp(self) -> None:
        self.parent = (ROOT / ".godot" / "offline-calibration-tests").resolve()
        self.parent.mkdir(parents=True, exist_ok=True)
        self.directory = self.parent / uuid.uuid4().hex
        self.directory.mkdir()
        self.addCleanup(self.cleanup_directory)
        self.plan = make_plan("1000", 3, 2, 2)
        self.plan_path = self.write("plan.json", self.plan)
        _, self.plan_hash, _ = read_object(self.plan_path)

    def cleanup_directory(self) -> None:
        if self.directory.resolve().parent != self.parent:
            raise RuntimeError("refusing cleanup outside the test workspace")
        shutil.rmtree(self.directory)

    def write(self, name: str, value: dict[str, Any]) -> Path:
        path = self.directory / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def rows(self, config: str = "synthetic-a") -> list[dict[str, str]]:
        return [{"run_id": f"{config}-{seed}", "source": "bot", "rules_version": RULE_VERSION,
                 "strategy": "synthetic-greedy", "config_hash": config, "mode_id": "stage_challenge", "seed": seed,
                 "content_version": "synthetic-content", "offer_version": OFFER_VERSION, "build": "synthetic-build",
                 "bot_config_hash": "synthetic-bot", "status": "completed", "reason": "board_full",
                 "replay_error": "", "record_complete": "true", "score": "0"} for seed in self.plan["seeds"]["smoke"]]

    def batch(self, rows: list[dict[str, str]], name: str = "runs.csv") -> Path:
        path = self.directory / name
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return path

    def index(self, rows: list[dict[str, str]], label: str = "a_0.0", name: str = "runs.csv") -> dict[str, Any]:
        return inventory(self.plan, self.plan_hash, self.batch(rows, name), "smoke", label)

    def pair(self) -> list[Path]:
        return [self.write("a.json", self.index(self.rows())),
                self.write("b.json", self.index(self.rows("synthetic-b"), "a_0.25", "b.csv"))]

    def cli(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(TOOL / "calibration_cli.py"), *arguments],
                              text=True, capture_output=True, timeout=10)

    def test_complete_index_only_claims_seed_metadata(self) -> None:
        result = self.index(self.rows())
        self.assertTrue(result["seed_inventory_complete"])
        self.assertEqual(result["metadata_qualified_seeds"], ["1000", "1001", "1002"])
        self.assertFalse(result["telemetry_coverage_verified"])
        self.assertFalse(result["ready_to_select_parameters"])
        self.assertIsNone(result["variant"]["actual_parameters"])
        self.assertIsNone(result["independent_parent_runs"])
        self.assertIn("runtime_parameter_binding_unverified", result["pending"])

    def test_missing_extra_and_censored_seeds_remain_visible(self) -> None:
        rows = self.rows()
        rows[0]["status"] = "censored"
        rows[0]["record_complete"] = "false"
        rows[0]["replay_error"] = "synthetic mismatch"
        rows[1]["seed"] = "9999"
        result = self.index(rows[:2])
        self.assertFalse(result["seed_inventory_complete"])
        self.assertEqual(result["extra_seeds"], ["9999"])
        self.assertEqual(result["missing_seeds"], ["1000", "1001", "1002"])
        self.assertEqual(len(result["records"]), 2)
        self.assertEqual(len(result["records"][0]["issues"]), 3)

    def test_exact_rows_alias_conflicting_run_ids_reject(self) -> None:
        rows = self.rows()
        result = self.index(rows + [copy.deepcopy(rows[0])])
        self.assertEqual(result["duplicate_input_rows"], 1)
        self.assertEqual(len(result["records"]), 3)
        self.assertTrue(result["seed_inventory_complete"])
        conflicting = copy.deepcopy(rows[0])
        conflicting["score"] = "1"
        with self.assertRaisesRegex(ValueError, "conflicting"):
            self.index(rows + [conflicting])

    def test_repeated_seed_and_mixed_strategy_or_config_block(self) -> None:
        rows = self.rows()
        repeated = copy.deepcopy(rows[0])
        repeated["run_id"] = "different-run"
        result = self.index(rows + [repeated])
        self.assertIn("multiple_run_ids_for_same_seed", result["errors"])
        self.assertNotIn("1000", result["metadata_qualified_seeds"])
        for key in ("config_hash", "strategy"):
            changed = self.rows()
            changed[0][key] = "different"
            self.assertIn("mixed_configuration_or_strategy_groups", self.index(changed)["errors"])

    def test_bad_csv_metadata_and_versions_reject(self) -> None:
        for key, value in [("seed", "01"), ("rules_version", "old"), ("offer_version", "unknown"),
                           ("config_hash", ""), ("run_id", "bad/id"), ("status", "true"), ("record_complete", "1")]:
            rows = self.rows()
            rows[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.index(rows)
        path = self.batch(self.rows())
        original = path.read_text(encoding="utf-8")
        for text in ["run_id,run_id\nx,x\n", original + "too,few\n", original.splitlines()[0] + "\n"]:
            path.write_text(text, encoding="utf-8")
            with self.assertRaises(ValueError):
                inventory(self.plan, self.plan_hash, path, "smoke", "baseline_observed")
        path.write_text(original, encoding="utf-8")
        with patch("cohort_inventory.MAX_ARTIFACT_BYTES", 8), self.assertRaises(ValueError):
            inventory(self.plan, self.plan_hash, path, "smoke", "a_0.0")

    def test_paired_seeds_do_not_establish_parameter_binding_or_independence(self) -> None:
        result = compare(self.plan, self.plan_hash, self.pair())
        self.assertTrue(result["seed_pairing_complete"])
        self.assertEqual(result["shared_metadata_qualified_seeds"], ["1000", "1001", "1002"])
        self.assertFalse(result["comparison_ready"])
        self.assertIsNone(result["parameter_acceptance"])
        self.assertIsNone(result["independent_parent_runs"])

    def test_relabelled_same_config_and_overlapping_runs_cannot_pair(self) -> None:
        a = self.write("a.json", self.index(self.rows()))
        b = self.write("b.json", self.index(self.rows(), "a_0.25"))
        result = compare(self.plan, self.plan_hash, [a, b])
        self.assertIn("same_configuration_for_distinct_labels", result["errors"])
        self.assertIn("run_identity_overlap_between_cohorts", result["errors"])
        self.assertFalse(compare(self.plan, self.plan_hash, [a, a])["seed_pairing_complete"])

    def test_incomplete_context_mismatch_and_duplicate_labels_block(self) -> None:
        a, b = self.pair()
        rows = self.rows("synthetic-b")
        rows[0]["status"] = "censored"
        b = self.write("b.json", self.index(rows, "a_0.25", "b.csv"))
        self.assertFalse(compare(self.plan, self.plan_hash, [a, b])["seed_pairing_complete"])
        rows = self.rows("synthetic-b")
        for row in rows:
            row["strategy"] = "different"
        b = self.write("b.json", self.index(rows, "a_0.0", "b.csv"))
        errors = compare(self.plan, self.plan_hash, [a, b])["errors"]
        self.assertIn("comparison_context_mismatch", errors)
        self.assertIn("duplicate_variant_label", errors)

    def test_malformed_or_contradictory_inventory_never_becomes_complete(self) -> None:
        a, b = self.pair()
        original = json.loads(b.read_text(encoding="utf-8"))
        for mutate in [lambda p: p.__setitem__("phase", []), lambda p: p.__setitem__("plan_sha256", "wrong"),
                       lambda p: p.__setitem__("groups", {"x": None}), lambda p: p.__setitem__("seed_inventory_complete", 1),
                       lambda p: p["variant"].__setitem__("actual_parameters", {"a": 0.25}),
                       lambda p: p["variant"].__setitem__("label", "unregistered"),
                       lambda p: p["records"][0].__setitem__("seed", "1001"),
                       lambda p: p["metadata_qualified_seeds"].append("1000")]:
            value = copy.deepcopy(original)
            mutate(value)
            self.write("b.json", value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                compare(self.plan, self.plan_hash, [a, b])
        self.write("b.json", original)
        with patch("cohort_inventory.MAX_TOTAL_BYTES", 8), self.assertRaises(ValueError):
            compare(self.plan, self.plan_hash, [a, b])

    def test_actual_index_compare_cli_and_no_overwrite(self) -> None:
        batch = self.batch(self.rows())
        original = batch.read_bytes()
        output = self.directory / "index.json"
        arguments = ["index", str(self.plan_path), str(batch), "--phase", "smoke", "--variant", "a_0.0", "--output", str(output)]
        self.assertEqual(self.cli(*arguments).returncode, 0)
        self.assertEqual(self.cli(*arguments).returncode, 2)
        self.assertEqual(batch.read_bytes(), original)
        self.batch(self.rows()[:1])
        arguments[-1] = str(self.directory / "missing.json")
        self.assertEqual(self.cli(*arguments).returncode, 1)
        a, b = self.pair()
        result = self.cli("compare", str(self.plan_path), str(a), str(b), "--output", str(self.directory / "pair.json"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.cli("compare", str(self.plan_path), str(a), str(a), "--output", str(self.directory / "alias.json")).returncode, 1)
        malformed = json.loads(b.read_text(encoding="utf-8"))
        malformed["phase"] = []
        self.write("b.json", malformed)
        result = self.cli("compare", str(self.plan_path), str(a), str(b), "--output", str(self.directory / "bad.json"))
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
