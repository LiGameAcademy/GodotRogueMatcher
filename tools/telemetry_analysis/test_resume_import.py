"""Resume ingestion keeps segments distinct while counting one logical run."""
from __future__ import annotations

import copy
import csv
import json
import shutil
import unittest
import uuid
import zipfile
from pathlib import Path

from import_sources import canonical, ingest


def parent() -> dict:
    return {"schema_version": "2", "run_id": "run1", "session_id": "parent-session",
            "event_id": "run1:1", "telemetry_seq": "1", "event_name": "run_started",
            "payload": {}}


def child() -> dict:
    return {"schema_version": "3", "run_id": "run1", "session_id": "child-session",
            "segment_id": "child-session", "event_id": "run1:child-session:1",
            "telemetry_seq": "1", "event_name": "run_resumed", "payload": {}}


class ResumeImportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parents[2] / ".godot" / ("resume-import-" + uuid.uuid4().hex)
        self.root.mkdir(parents=True)

    def tearDown(self) -> None:
        self.assertTrue(self.root.resolve().is_relative_to(Path(__file__).resolve().parents[2] / ".godot"))
        shutil.rmtree(self.root)

    def write(self, name: str, rows: list[dict]) -> Path:
        path = self.root / name
        path.write_text("".join(canonical(row) + "\n" for row in rows), encoding="utf-8")
        return path

    def test_parent_and_resume_stage_as_two_streams_and_one_logical_run(self) -> None:
        result = ingest([self.write("parent.jsonl", [parent()]),
                         self.write("child.jsonl", [child()])], self.root / "out")
        self.assertEqual(result["diagnostics"], [])
        self.assertEqual(result["runs"], 1)
        self.assertEqual(result["segments"], 2)
        self.assertEqual(result["events"], 2)
        self.assertEqual(len(list((self.root / "out").glob("*.jsonl"))), 2)

    def test_bad_segment_identity_is_diagnostic_instead_of_uncaught_grouping_error(self) -> None:
        cases = [None, 12, [], "", "other-session"]
        for index, value in enumerate(cases):
            row = child()
            if value is None:
                row.pop("segment_id")
            else:
                row["segment_id"] = value
            result = ingest([self.write(f"bad-{index}.jsonl", [row])], self.root / f"out-{index}")
            self.assertEqual(result["runs"], 0)
            self.assertTrue(any(item["reason"] == "invalid_resume_segment" for item in result["diagnostics"]))

    def test_export_zip_snapshot_commands_do_not_reject_valid_telemetry_for_same_run(self) -> None:
        header = {"kind": "SnapshotHeader", "schema_version": "run-snapshot-segment-v1",
                  "run_id": "run1", "segment_id": "child-session", "seq": "1"}
        package = self.root / "web-records.zip"
        with zipfile.ZipFile(package, "w") as archive:
            archive.writestr("telemetry/parent.jsonl", canonical(parent()) + "\n")
            archive.writestr("telemetry/child.jsonl", canonical(child()) + "\n")
            archive.writestr("run_records/run1--child-session.jsonl", canonical(header) + "\n")
        result = ingest([package], self.root / "out")
        self.assertEqual(result["diagnostics"], [])
        self.assertEqual((result["runs"], result["segments"], result["events"]), (1, 2, 2))
        self.assertEqual(result["rejected_runs"], [])
        inventory = result["files"]
        self.assertTrue(any(row.get("kind") == "rule_record_evidence_not_telemetry"
                            for row in inventory))

    def test_unknown_snapshot_header_schema_is_not_silently_skipped(self) -> None:
        header = {"kind": "SnapshotHeader", "schema_version": "unknown",
                  "run_id": "run1", "segment_id": "child-session", "seq": "1"}
        result = ingest([self.write("unknown.jsonl", [header])], self.root / "out")
        self.assertEqual(result["runs"], 0)
        self.assertTrue(any(row["reason"] == "invalid_event_identity" for row in result["diagnostics"]))

    def test_renamed_lineage_document_uses_schema_not_filename_for_multiple_segments(self) -> None:
        path = self.root / "renamed-evidence.json"
        path.write_text(json.dumps({"schema": "telemetry-lineage-analysis-v1",
                                    "raw_events": [parent(), child()]}), encoding="utf-8")
        result = ingest([path], self.root / "out")
        self.assertEqual(result["diagnostics"], [])
        self.assertEqual((result["runs"], result["segments"], result["events"]), (1, 2, 2))

    def test_derived_csv_and_original_segments_reimport_without_conflicting_or_extra_samples(self) -> None:
        path = self.root / "events.csv"
        originals = [parent(), child()]
        with path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=["event_json"])
            writer.writeheader()
            for index, raw in enumerate(originals, 1):
                view = copy.deepcopy(raw)
                view.update(schema_version="2", session_id="parent-session", event_id=f"run1:{index}",
                            telemetry_seq=str(index), resume_reassembled=True,
                            source_event_id=raw["event_id"], source_event=raw)
                writer.writerow({"event_json": canonical(view)})
        result = ingest([path, self.write("parent.jsonl", [parent()]),
                         self.write("child.jsonl", [child()])], self.root / "out")
        self.assertEqual(result["diagnostics"], [])
        self.assertEqual((result["runs"], result["segments"], result["events"]), (1, 2, 2))

    def test_invalid_derived_source_cannot_fall_back_to_ingesting_the_unverified_view(self) -> None:
        path = self.root / "events.csv"
        raw = parent()
        good = dict(raw, resume_reassembled=True, source_event_id=raw["event_id"], source_event=raw)
        bad = dict(raw, event_id="run1:2", telemetry_seq="2", event_name="ui_observed",
                   resume_reassembled=True, source_event_id="run1:child-session:1", source_event=[])
        with path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=["event_json"])
            writer.writeheader()
            for row in [good, bad]:
                writer.writerow({"event_json": canonical(row)})
        result = ingest([path], self.root / "out")
        self.assertEqual(result["events"], 1)
        self.assertTrue(any(row["reason"] == "invalid_resume_analysis_source" for row in result["diagnostics"]))

    def test_failed_segment_summary_stays_diagnostic_after_new_segment(self) -> None:
        summary = self.root / "failed.summary.json"
        summary.write_text(json.dumps({"run_id": "run1", "segment_id": "parent-session",
                           "data_integrity": "write_failed", "telemetry_error": "flush_failed"}), encoding="utf-8")
        result = ingest([self.write("parent.jsonl", [parent()]),
                         self.write("child.jsonl", [child()]), summary], self.root / "out")
        self.assertEqual(result["runs"], 1)
        self.assertTrue(any(row["reason"] == "telemetry_segment_write_failed"
                            for row in result["diagnostics"]))


if __name__ == "__main__":
    unittest.main()
