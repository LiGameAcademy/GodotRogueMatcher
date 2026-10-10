"""Behavior regressions for ingestion, denominators and reference preservation."""
from __future__ import annotations

import copy
import csv
import json
import shutil
import unittest
import uuid
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

from import_sources import canonical, ingest
from model_statistics import Metrics, analyze, digest, quantile, wilson
from xlsx_append import cell_value, NS


def event(seq: int, name: str, payload: dict, run: str = "run1", context: str = "editor_playtest") -> dict:
    return {"event_id": f"{run}:{seq}", "run_id": run, "telemetry_seq": str(seq),
            "event_name": name, "schema_version":"2", "source":"human",
            "collection_context":context, "mode_id":"stage_challenge", "rule_version":"rules1",
            "config_hash":"cfg1", "payload": payload}


def action(seq: int, score: int = 0, run: str = "run1") -> dict:
    return event(seq,"action_resolved", {"complete": True, "space_consistent": True,
        "created_ids":["1"],"removed_ids":[],"created":"1","removed":"0",
        "ledger_entries":([] if not score else [{"final_score":str(score)}]),
        "action_score_delta":str(score),"action_type":"move", "build_before":{},
        "P_before":{"P":30.0}, "P_after":{"P":31.0}, "q_frozen":"3",
        "stage_before":{"enabled":True,"stage_id":"1"}},run)


class ImportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parents[2]/".godot"/("model-test-"+uuid.uuid4().hex)
        self.root.mkdir(parents=True)

    def tearDown(self) -> None:
        self.assertTrue(self.root.resolve().is_relative_to(Path(__file__).resolve().parents[2]/".godot"))
        shutil.rmtree(self.root)

    def write(self, name: str, values: list[dict], ending: str = "\n") -> Path:
        file = self.root/name
        file.write_text("\n".join(canonical(e) for e in values)+ending,encoding="utf-8")
        return file

    def test_duplicate_and_complete_suffix_replace_prefix(self) -> None:
        rows=[event(1,"run_started",{}),action(2),event(3,"run_ended",{"record_complete":True})]
        prefix=self.write("a.jsonl",rows[:2])
        complete=self.write("b.jsonl",rows)
        first=ingest([complete],self.root/"out1")
        duplicate=ingest([prefix,complete,complete,prefix],self.root/"out2")
        self.assertEqual(first["dataset_hash"],duplicate["dataset_hash"])
        self.assertEqual((1,3),(duplicate["runs"],duplicate["events"]))

    def test_same_id_conflict_rejects_whole_run(self) -> None:
        a=self.write("a.jsonl",[event(1,"run_started",{}),action(2)])
        b=self.write("b.jsonl",[event(1,"run_started",{}),action(2,50)])
        result=ingest([a,b],self.root/"out")
        self.assertEqual(["run1"],result["rejected_runs"])
        self.assertEqual(0,result["runs"])

    def test_metadata_cannot_change_in_middle_of_run(self) -> None:
        changed=action(2)
        changed["mode_id"]="classic"
        raw=self.write("a.jsonl",[event(1,"run_started",{}),changed])
        result=ingest([raw],self.root/"out")
        self.assertEqual(["run1"],result["rejected_runs"])

    def test_game_export_keeps_session_and_recorder_out_of_rule_samples(self) -> None:
        archive=self.root/"pack.zip"
        with zipfile.ZipFile(archive,"w") as output:
            output.writestr("telemetry/run1.jsonl",canonical(event(1,"run_started",{}))+"\n")
            output.writestr("run_records/run1.jsonl",canonical({"kind":"Header","run_id":"run1"})+"\n")
            output.writestr("sessions/s.jsonl",canonical({"session_schema":"collection-session-v1",
                "seq":"1","event":"session_started","payload":{"session_id":"s"}})+"\n")
        result=ingest([archive],self.root/"out")
        self.assertEqual(1,result["events"])
        self.assertEqual(1,len(result["sessions"]))
        self.assertEqual([],result["diagnostics"])

    def test_session_suffix_replaces_duplicate_prefix(self) -> None:
        start={"session_schema":"collection-session-v1","seq":"1","event":"session_started",
               "payload":{"session_id":"s"}}
        end={"session_schema":"collection-session-v1","seq":"2","event":"session_closed","payload":{"reason":"window_close"}}
        prefix=self.write("session_prefix.jsonl",[start])
        complete=self.write("session_complete.jsonl",[start,end])
        result=ingest([prefix,complete,prefix],self.root/"out")
        self.assertEqual(1,len(result["sessions"]))
        self.assertEqual(2,len(result["sessions"][0]["records"]))

    def test_partial_line_is_not_success(self) -> None:
        file=self.write("partial.jsonl",[event(1,"run_started",{}),action(2)],ending="")
        result=ingest([file],self.root/"out")
        self.assertEqual(1,result["events"])
        self.assertEqual("incomplete_last_line",result["diagnostics"][0]["reason"])

    def test_sequence_gap_rejects_run(self) -> None:
        file=self.write("gap.jsonl",[event(1,"run_started",{}),action(3)])
        result=ingest([file],self.root/"out")
        self.assertEqual(0,result["events"])

    def test_zip_does_not_extract_member_paths(self) -> None:
        archive=self.root/"pack.zip"
        with zipfile.ZipFile(archive,"w") as zipfile_out:
            zipfile_out.writestr("../../escape.jsonl",canonical(event(1,"run_started",{}))+"\n")
        result=ingest([archive],self.root/"out")
        self.assertEqual(1,result["events"])
        self.assertFalse((self.root.parent/"escape.jsonl").exists())

    def test_lossless_csv_and_jsonl_deduplicate(self) -> None:
        rows=[event(1,"run_started",{}),action(2)]
        raw=self.write("a.jsonl",rows)
        file=self.root/"events.csv"
        with file.open("w",encoding="utf-8",newline="") as output:
            writer=csv.writer(output)
            writer.writerow(["event_json"])
            for row in rows: writer.writerow([canonical(row)])
        result=ingest([file,raw],self.root/"out")
        self.assertEqual(2,result["events"])

    def test_old_lossy_csv_is_explicit_limitation(self) -> None:
        file=self.root/"events.csv"
        file.write_text("run_id,event_id\nrun1,run1:1\n",encoding="utf-8")
        result=ingest([file],self.root/"out")
        self.assertEqual("lossy_csv_requires_original_jsonl",result["diagnostics"][0]["reason"])

    def test_summary_cannot_override_events(self) -> None:
        raw=self.write("a.jsonl",[event(1,"run_started",{}),event(2,"run_ended",{"score":"50"})])
        summary=self.root/"run.summary.json"
        summary.write_text(json.dumps({"run_id":"run1","score":"100"}))
        result=ingest([raw,summary],self.root/"out")
        self.assertEqual(["run1"],result["rejected_runs"])

    def test_malformed_session_is_diagnostic_not_crash(self) -> None:
        source=self.write("session.jsonl",[{"session_schema":"collection-session-v1","payload":[]}])
        result=ingest([source],self.root/"out")
        self.assertEqual([],result["sessions"])
        self.assertEqual("invalid_session_sequence_or_schema",result["diagnostics"][0]["reason"])

    def test_missing_input_is_not_silently_skipped(self) -> None:
        valid=self.write("valid.jsonl",[event(1,"run_started",{})])
        with self.assertRaisesRegex(ValueError,"input source does not exist"):
            ingest([valid,self.root/"missing.jsonl"],self.root/"out")

    def test_invalid_summary_identity_is_diagnostic(self) -> None:
        source=self.root/"invalid.summary.json"
        source.write_text('{"run_id":[]}',encoding="utf-8")
        result=ingest([source],self.root/"out")
        self.assertEqual("invalid_summary_run_id",result["diagnostics"][0]["reason"])

    def test_missing_csv_event_json_is_diagnostic(self) -> None:
        source=self.root/"events.csv"
        source.write_text("run_id,event_json\nrun1\n",encoding="utf-8")
        result=ingest([source],self.root/"out")
        self.assertEqual(0,result["events"])
        self.assertTrue(result["diagnostics"])


class StatisticTests(unittest.TestCase):
    def metric(self, rows: list[dict], metric: str) -> dict:
        return next(r for r in analyze(rows,repetitions=100)["metrics"] if r["metric_id"]==metric)

    def test_valid_zero_differs_from_unknown(self) -> None:
        rows=[event(1,"run_started",{}),action(2)]
        zero=self.metric(rows,"action_score")
        missing=self.metric(rows,"p_direct")
        self.assertEqual((0,1),(zero["value"],zero["denominator"]))
        self.assertEqual((None,0),(missing["value"],missing["denominator"]))

    def test_corrupt_ledger_is_not_counted(self) -> None:
        bad=action(2,50)
        bad["payload"]["ledger_entries"]=[]
        self.assertIsNone(self.metric([event(1,"run_started",{}),bad],"action_score")["value"])

    def test_acquisition_does_not_pollute_action_score(self) -> None:
        rows=[event(1,"run_started",{}),action(2,50),event(3,"skill_acquired",{
            "offer_id":"1","skill_id":"test","count_after":"1","score_delta":"100","net_empty":"-1"})]
        self.assertEqual(50,self.metric(rows,"action_score")["value"])
        self.assertEqual(100,self.metric(rows,"choice_score")["value"])

    def test_human_opportunity_is_unique_presented_offer(self) -> None:
        rows=[event(1,"run_started",{}),event(2,"offer_generated",{"offer_id":"1","choices":["test","test"]}),
              event(3,"offer_presented",{"offer_id":"1"}),event(4,"offer_presented",{"offer_id":"1"})]
        row=self.metric(rows,"selection_rate")
        self.assertEqual((0,1),(row["value"],row["denominator"]))

    def test_unknown_human_fixture_is_not_real_opportunity(self) -> None:
        rows=[event(1,"run_started",{},context="unknown"),event(2,"offer_generated",{"offer_id":"1","choices":["test"]}),
              event(3,"offer_presented",{"offer_id":"1"})]
        self.assertIsNone(self.metric(rows,"selection_rate")["value"])

    def test_abandoned_stage_is_not_gameplay_failure(self) -> None:
        rows=[event(1,"run_started",{}),action(2),event(3,"run_ended",{"status":"abandoned","record_complete":True})]
        self.assertIsNone(self.metric(rows,"stage_completion")["value"])
        self.assertEqual("user_stop",analyze(rows)["exits"][0]["end_class"])

    def test_modes_and_contexts_do_not_mix(self) -> None:
        a=[event(1,"run_started",{}),action(2)]
        b=copy.deepcopy(a)
        for row in b:
            row["run_id"]="run2"
            row["event_id"]=row["event_id"].replace("run1","run2")
            row["mode_id"]="classic"
        self.assertEqual(2,len(analyze(a+b)["groups"]))

    def test_rule_error_prefix_cannot_become_reference(self) -> None:
        rows=[event(1,"run_started",{}),action(2),event(3,"run_ended",{
            "status":"rule_error","record_complete":True})]
        row=next(r for r in analyze(rows,min_runs=1,min_events=1)["metrics"] if r["metric_id"]=="action_score")
        self.assertEqual("dataset_diagnostics_require_review",row["quality"])
        self.assertEqual(0,row["value"])

    def test_bootstrap_is_by_run_and_reproducible(self) -> None:
        metric=Metrics({"schema_version":"2","collection_context":"bot_batch"},seed=7,repetitions=100)
        for run,score in [("a",0),("a",0),("b",100)]:
            metric.add("score","points",{"run_id":run,"event_id":run},score)
        row=metric.finish(30,100)[0]
        self.assertEqual(2,row["n_runs"])
        self.assertEqual(3,row["n_events"])
        self.assertEqual("insufficient_samples",row["quality"])
        self.assertEqual([0,100],row["ci95"])

    def test_repeated_bot_seed_does_not_supply_independent_clusters(self) -> None:
        metric=Metrics({"source":"bot","schema_version":"2","collection_context":"bot_batch"})
        for index in range(30):
            for action_index in range(4):
                metric.add("score","points",{"run_id":str(index),"event_id":str(action_index),"seed":"7"},1)
        row=metric.finish(30,100)[0]
        self.assertEqual((30,1,120),(row["n_runs"],row["n_clusters"],row["n_events"]))
        self.assertEqual("insufficient_samples",row["quality"])

    def test_quantile_and_wilson_boundary(self) -> None:
        self.assertEqual(1,quantile([1,2],.9))
        self.assertIsNone(wilson(0,0))
        self.assertEqual(0,wilson(0,10)[0])
        self.assertAlmostEqual(1,wilson(10,10)[1])

    def test_unseen_catalog_skill_stays_unknown(self) -> None:
        rows=[event(1,"run_started",{"config":{"skills":[{"skill_id":"rare_skill"}]}})]
        row=self.metric(rows,"selection_rate")
        self.assertEqual("rare_skill",row["skill_id"])
        self.assertIsNone(row["value"])

    def test_skill_exposure_counts_only_installed_level(self) -> None:
        before=action(2)
        after=action(3)
        after["payload"]["build_before"]={"test":"2"}
        rows=[event(1,"run_started",{}),before,after]
        row=self.metric(rows,"skill_action_exposure")
        self.assertEqual((1,1,2),(row["value"],row["denominator"],row["level"]))


class WorkbookValueTests(unittest.TestCase):
    def test_artifact_plain_text_and_shared_strings_read_back(self) -> None:
        for kind, raw, expected in [("str","semantic-key","semantic-key"),("s","0","semantic-key"),
                                    ("b","1",True),("n","0",0.0)]:
            node=ET.fromstring(f'<c xmlns="{NS}" t="{kind}"><v>{raw}</v></c>')
            self.assertEqual(expected,cell_value(node,["semantic-key"]))

    def test_formula_is_preserved_as_formula(self) -> None:
        node=ET.fromstring(f'<c xmlns="{NS}"><f>SUM(A1:A2)</f><v>0</v></c>')
        self.assertEqual("=SUM(A1:A2)",cell_value(node,[]))


if __name__ == "__main__":
    unittest.main()
