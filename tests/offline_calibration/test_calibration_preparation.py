"""Self-contained preparation tests; fixtures never count as gameplay evidence."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import sys
import shutil
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "random_calibration"
sys.path.insert(0, str(TOOL))
from calibration_plan import MAX_SEED, make_plan, seed_value, validate_plan
from report_preflight import audit, inspect_summary, read_object


class PreparationTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary_root = ROOT / ".godot" / "offline-calibration-tests"
        temporary_root.mkdir(parents=True, exist_ok=True)
        self.directory = (temporary_root / uuid.uuid4().hex).resolve()
        self.assertTrue(self.directory.is_relative_to(temporary_root.resolve()))
        self.directory.mkdir()
        self.addCleanup(self.cleanup_directory)
        self.fixture = json.loads(Path(__file__).with_name("summary_fixture.json").read_text(encoding="utf-8"))

    def cleanup_directory(self) -> None:
        expected_parent = (ROOT / ".godot" / "offline-calibration-tests").resolve()
        if self.directory.resolve().parent != expected_parent:
            raise RuntimeError("refusing cleanup outside the test workspace")
        shutil.rmtree(self.directory)

    def write(self, name: str, value: dict) -> Path:
        path = self.directory / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def cli(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(TOOL / "calibration_cli.py"), *arguments], text=True, capture_output=True, timeout=10)

    def test_seed_boundaries_and_canonical_encoding(self) -> None:
        self.assertEqual(seed_value("0"), 0)
        self.assertEqual(seed_value(str(MAX_SEED)), MAX_SEED)
        for value in ["01", "+1", "-1", "1e2", "1.0", " 1", "１", "1\n", str(MAX_SEED + 1), 1, True]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                seed_value(value)

    def test_staged_seed_inventory_is_disjoint_and_not_a_cartesian_scan(self) -> None:
        plan = make_plan("1000")
        self.assertEqual([len(plan["seeds"][phase]) for phase in ("smoke", "explore", "confirm")], [3, 100, 150])
        values = [seed for seeds in plan["seeds"].values() for seed in seeds]
        self.assertEqual(len(values), len(set(values)))
        self.assertEqual(len(plan["related_scan"]), 3)
        self.assertIsNone(plan["gap_scan"]["selected_a"])
        self.assertIsNone(plan["parameter_acceptance"])
        self.assertIn("runner_parameter_injection_unavailable", validate_plan(plan))
        self.assertEqual(len([value for value in validate_plan(plan) if value.startswith("unregistered_criterion:")]), 4)

    def test_bad_registration_is_rejected_instead_of_rewriting_parameters(self) -> None:
        for mutate in [
            lambda p: p["seeds"]["confirm"].__setitem__(0, p["seeds"]["smoke"][0]),
            lambda p: p["related_scan"][0].__setitem__("a", False),
            lambda p: p.__setitem__("parameter_acceptance", {"a": 0.5}),
            lambda p: p["runner"].__setitem__("parameter_override_supported", True),
            lambda p: p["criteria"].__setitem__("maximum_runs", True),
            lambda p: p["criteria"].__setitem__("maximum_uncertainty", 0.5),
        ]:
            plan = make_plan("0")
            mutate(plan)
            with self.assertRaises(ValueError):
                validate_plan(plan)
        with self.assertRaises(ValueError):
            make_plan(str(MAX_SEED))
        with self.assertRaises(ValueError):
            make_plan("0", smoke=True)

    def test_summary_preflight_does_not_claim_parameter_acceptance_or_seed_counts(self) -> None:
        path = self.write("report.json", self.fixture)
        result = audit(make_plan("1000"), [path])
        self.assertTrue(result["summary_preflight_valid"])
        self.assertFalse(result["ready_to_select_parameters"])
        self.assertIsNone(result["parameter_acceptance"])
        self.assertIsNone(result["artifacts"][0]["independent_parent_runs"])
        self.assertEqual(result["artifacts"][0]["reported_runs"], 3)

    def test_bad_quality_unknown_versions_and_missing_pool_coverage_are_blocked(self) -> None:
        mutations = [
            lambda s: s.__setitem__("errors", [{"reason": "unsupported_resume"}]),
            lambda s: s["bounded"].__setitem__("complete", False),
            lambda s: s.__setitem__("resume_branches", []),
            lambda s: s["groups"]["synthetic-bot-group"]["dimensions"].__setitem__("schema_version", "3"),
            lambda s: s["groups"]["synthetic-bot-group"]["dimensions"].__setitem__("offer_version", "offer-unified-trial-v3"),
            lambda s: s["groups"]["synthetic-bot-group"]["dimensions"].__setitem__("config_hash", "unknown"),
            lambda s: s["opportunities"]["pool_audit"].__setitem__("complete_rewards", 0),
            lambda s: s["opportunities"]["pool_audit"].__setitem__("complete_rate", None),
            lambda s: s["opportunities"]["pool_audit"].__setitem__("complete_rate", True),
            lambda s: s.__setitem__("runs", 4),
        ]
        for index, mutate in enumerate(mutations):
            summary = copy.deepcopy(self.fixture)
            mutate(summary)
            with self.subTest(index=index):
                self.assertTrue(inspect_summary(summary)[0])

    def test_censored_and_fixture_groups_are_visible_not_silently_discarded(self) -> None:
        self.fixture["groups"]["synthetic-bot-group"]["status"] = "censored"
        self.fixture["groups"]["synthetic-bot-group"]["dimensions"]["initialization"] = "fixture_f6"
        result = audit(make_plan("1000"), [self.write("report.json", self.fixture)])
        row = result["artifacts"][0]
        self.assertEqual(row["reported_runs"], 3)
        self.assertEqual(len(row["pending"]), 2)
        self.assertFalse(result["ready_to_select_parameters"])

    def test_exact_duplicates_are_aliases_but_overlapping_artifacts_are_never_summed(self) -> None:
        first = self.write("a.json", self.fixture)
        second = self.write("b.json", self.fixture)
        changed = copy.deepcopy(self.fixture)
        changed["fixture_note"] = "same samples; different export metadata"
        third = self.write("c.json", changed)
        result = audit(make_plan("1000"), [first, second, third])
        self.assertEqual(len(result["artifacts"]), 2)
        self.assertEqual(len(result["artifacts"][0]["aliases"]), 1)
        self.assertNotIn("total_runs", result)
        self.assertIn("cross_artifact_overlap_unknown_no_totals", result["pending"])

    def test_invalid_json_and_input_limits_fail_explicitly(self) -> None:
        for raw in ['{"runs":1,"runs":2}', '{"x":NaN}', '{"x":1e400}', '[]']:
            path = self.directory / "bad.json"
            path.write_text(raw, encoding="utf-8")
            with self.assertRaises(ValueError):
                read_object(path)
        path = self.write("report.json", self.fixture)
        with patch("report_preflight.MAX_ARTIFACT_BYTES", 16), self.assertRaises(ValueError):
            read_object(path)
        with patch("report_preflight.MAX_TOTAL_BYTES", 16), self.assertRaises(ValueError):
            audit(make_plan("1000"), [path])
        with self.assertRaises(ValueError):
            audit(make_plan("1000"), [])

    def test_actual_cli_exit_codes_and_output_no_overwrite(self) -> None:
        plan = self.directory / "plan.json"
        self.assertEqual(self.cli("plan", "--first-seed", "1000", "--output", str(plan)).returncode, 0)
        original = plan.read_bytes()
        self.assertEqual(self.cli("plan", "--first-seed", "1001", "--output", str(plan)).returncode, 2)
        self.assertEqual(plan.read_bytes(), original)
        valid = self.write("valid.json", self.fixture)
        output = self.directory / "audit.json"
        self.assertEqual(self.cli("audit", str(plan), str(valid), "--output", str(output)).returncode, 0)
        self.assertIsNone(json.loads(output.read_text(encoding="utf-8"))["parameter_acceptance"])
        self.fixture["resume_branches"] = []
        invalid = self.write("resume.json", self.fixture)
        self.assertEqual(self.cli("audit", str(plan), str(invalid), "--output", str(self.directory / "blocked.json")).returncode, 1)

    def test_large_finite_integer_criterion_does_not_raise_float_overflow(self) -> None:
        registration = make_plan("1000")
        registration["criteria"]["minimum_meaningful_effect"] = 10 ** 400
        registration["criterion_units"]["minimum_meaningful_effect"] = "score points"
        plan = self.write("plan.json", registration)
        report = self.write("report.json", self.fixture)
        output = self.directory / "preflight.json"
        result = self.cli("audit", str(plan), str(report), "--output", str(output))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(json.loads(output.read_text(encoding="utf-8"))["ready_to_select_parameters"])


if __name__ == "__main__":
    unittest.main()
