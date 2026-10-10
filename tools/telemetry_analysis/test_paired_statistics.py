"""Paired observations retain horizon, comparator, censoring and parent clusters."""
import unittest

from model_statistics import analyze
from test_model_import import event


class PairedStatisticsTests(unittest.TestCase):
    def rows(self, run, parent, horizon, delta, control="other"):
        rows = [event(1, "run_started", {}, run, "fixture"),
                event(2, "paired_window_resolved", {
                    "pair_id": run, "parent_run_id": parent, "protocol": "legal-choice-window-v1",
                    "skill_id": "skill", "control_skill_id": control, "level": "1",
                    "H": str(horizon), "known": delta is not None, "delta_score": delta,
                    "delta_space": -2 if delta is not None else None,
                    "missing_reason": "externally_censored_window" if delta is None else ""}, run, "fixture"),
                event(3, "run_ended", {"record_complete": True, "status": "censored"}, run, "fixture")]
        for row in rows:
            row["source"] = "fixture"
        return rows

    def test_whole_window_once_negative_and_censored_not_zero(self):
        result = analyze(self.rows("a", "parent", 20, -10) + self.rows("b", "parent", 20, None))
        score = next(row for row in result["metrics"] if row["metric_id"] == "paired_score")
        self.assertEqual((score["value"], score["denominator"], score["missing"]), (-10, 1, 1))
        self.assertEqual(score["source_refs"], ["a:2"])

    def test_horizons_comparators_separate_and_original_run_clusters(self):
        result = analyze(self.rows("a", "parent", 20, 10) + self.rows("b", "parent", 20, 20)
                         + self.rows("c", "parent", 50, 30) + self.rows("d", "parent", 20, 40, "third"))
        scores = [row for row in result["metrics"] if row["metric_id"] == "paired_score"]
        self.assertEqual(len(scores), 3)
        row = next(row for row in scores if row["H"] == 20 and row["control_skill_id"] == "other")
        self.assertEqual((row["value"], row["n_runs"], row["n_clusters"]), (15, 2, 1))
        self.assertEqual(row["quality"], "insufficient_samples")

    def test_duplicate_window_is_rejected(self):
        rows = self.rows("a", "parent", 20, 10)
        duplicate = dict(rows[1], event_id="a:3", telemetry_seq="3")
        rows.insert(2, duplicate)
        rows[-1]["telemetry_seq"] = "4"
        with self.assertRaises(ValueError):
            analyze(rows)


if __name__ == "__main__":
    unittest.main()
