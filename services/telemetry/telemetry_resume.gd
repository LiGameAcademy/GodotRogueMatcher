class_name TelemetryResume
extends RefCounted

## Observation lineage only. Missing telemetry never mutates or rejects a verified rule run.
static func header(run: RunController, context: Dictionary, collection_context: String, commit_id: String) -> Dictionary:
	var row: Dictionary = run.recorder.records[0].duplicate(true)
	row.initial = RunSnapshot.capture(run)
	row.metadata["collection_context"] = collection_context
	row.metadata["commit_id"] = commit_id
	var trace: Dictionary = context.get("trace", {})
	var known: bool = _trace_valid(trace, run)
	row.metadata["resume"] = {"schema": "telemetry-resume-v1", "run_id": run.state.run_id, "checkpoint_id": String(context.get("checkpoint_id", "unknown")), "parent_segment_id": trace.segment_id if known else "", "parent_telemetry_seq": trace.accepted_seq if known else "0", "parent_persisted_seq": trace.persisted_seq if known else "0", "parent_last_event_id": trace.last_event_id if known else "", "record_seq": str(run.recorder.records.size()), "next_rule_event_id": str(run.state.ledger.next_event_id()), "anchor_state_hash": RunSnapshot.digest(row.initial), "lineage_known": known}
	row.metadata.resume["parent_last_event_hash"] = trace.last_event_hash if known else ""
	return row

static func _trace_valid(trace: Dictionary, run: RunController) -> bool:
	if trace.get("schema") != "checkpoint-telemetry-v1" or trace.get("run_id") != run.state.run_id: return false
	if not trace.get("segment_id") is String or not TelemetrySchema.safe_id(trace.segment_id): return false
	for key: String in ["accepted_seq", "persisted_seq", "record_seq", "next_rule_event_id"]:
		if not TelemetrySchema.valid_integer(trace.get(key)) or trace[key].to_int() < 0: return false
	if trace.accepted_seq.to_int() <= 0 or trace.persisted_seq.to_int() > trace.accepted_seq.to_int(): return false
	if trace.record_seq != str(run.recorder.records.size()) or trace.next_rule_event_id != str(run.state.ledger.next_event_id()): return false
	if not trace.get("last_event_hash") is String or RegEx.create_from_string("^[0-9a-f]{64}$").search(trace.last_event_hash) == null: return false
	return trace.get("last_event_id") in [run.state.run_id + ":" + trace.accepted_seq, run.state.run_id + ":" + trace.segment_id + ":" + trace.accepted_seq]
