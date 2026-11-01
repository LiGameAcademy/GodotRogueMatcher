extends RefCounted

## Snapshot-anchored command/evidence segments, separate from ordinary opening replay headers.
## Missing/unverified telemetry remains unknown and never blocks valid rule continuation.
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const RESTORE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const V: Script = preload("res://services/run_checkpoint/snapshot_values.gd")

static func trace(run: RunController, projector: TelemetryProjector) -> Dictionary:
	if run.recorder == null or projector.events.is_empty(): return {}
	var trace_value: Dictionary = projector.checkpoint_trace(run.recorder.records.size(), run.state.ledger.next_event_id())
	var row: Dictionary = projector.events.back()
	trace_value["snapshot_state_hash"] = RunSnapshot.digest(RESTORE.project(run))
	return trace_value if valid_trace(trace_value, trace_value.snapshot_state_hash, run.state.run_id) and _parent_matches(trace_value, row) else {}

static func valid_trace(value: Variant, state_hash: String, run_id: String) -> bool:
	if not value is Dictionary or JSON.stringify(value).length() > 2048: return false
	if value.get("schema") != "checkpoint-telemetry-v1" or value.get("run_id") != run_id or value.get("snapshot_state_hash") != state_hash: return false
	if not value.get("segment_id") is String or not TelemetrySchema.safe_id(value.segment_id): return false
	for key: String in ["accepted_seq", "persisted_seq", "record_seq", "next_rule_event_id"]:
		if not V.integer(value.get(key), 1): return false
	if value.accepted_seq != value.persisted_seq: return false
	for key: String in ["last_event_id", "last_event_hash"]:
		if not value.get(key) is String: return false
	return RegEx.create_from_string("^[0-9a-f]{64}$").search(value.last_event_hash) != null

static func begin(run: RunController, segment_id: String, context: Dictionary = {}, factory: TelemetryFactory = null) -> Dictionary:
	if run.recorder != null or run.state.ledger.history_size() != 0 or not TelemetrySchema.safe_id(segment_id) or (factory != null and factory.session_id != segment_id): return {"ok": false, "reason": "segment_owner_or_id_invalid"}
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	if not frozen.ok: return frozen
	var checked: Dictionary = SNAPSHOT.decode(frozen.payload, SNAPSHOT.manifest(run))
	if not checked.ok: return checked
	var trace_value: Dictionary = context.get("trace", {}) if context.get("trace", {}) is Dictionary else {}
	var parent: Variant = context.get("parent_event")
	var known: bool = valid_trace(trace_value, frozen.payload.state_hash, run.state.run_id) and parent is Dictionary and _parent_matches(trace_value, parent)
	var resume: Dictionary = {"schema": "telemetry-resume-v1", "run_id": run.state.run_id, "checkpoint_id": frozen.payload.state_hash, "parent_segment_id": trace_value.segment_id if known else "", "parent_telemetry_seq": trace_value.accepted_seq if known else "0", "parent_persisted_seq": trace_value.persisted_seq if known else "0", "parent_last_event_id": trace_value.last_event_id if known else "", "parent_last_event_hash": trace_value.last_event_hash if known else "", "record_seq": trace_value.record_seq if known else "0", "next_rule_event_id": str(run.state.ledger.next_event_id()), "anchor_state_hash": RunSnapshot.digest(RunSnapshot.capture(run, false)), "lineage_known": known, "protocol": "snapshot-command-segment-v1", "snapshot_state_hash": frozen.payload.state_hash, "unfinished_root_observation": "unknown"}
	var recorder: RunRecorder = RunRecorder.new()
	if factory != null:
		recorder.metadata = {"collection_context": factory.collection_context, "commit_id": factory.commit_id}
	var execution_source: String = parent.source if known else (context.source if context.get("source") is String else "unknown")
	recorder.begin_snapshot(run, frozen.payload, segment_id, execution_source, resume)
	run.recorder = recorder
	var projector: TelemetryProjector = null
	if factory != null:
		if factory.session_id != segment_id:
			run.recorder = null
			return {"ok": false, "reason": "segment_factory_identity_mismatch"}
		projector = factory.attach(recorder, run.state.run_id + "--" + segment_id)
		projector.begin_resume(recorder.records[0], [])
	return {"ok": true, "reason": "", "recorder": recorder, "projector": projector, "lineage_known": known}

static func replay(records: Array[Dictionary], expected_manifest: Dictionary) -> Dictionary:
	if records.is_empty() or records.size() > 4096 or not RunCheckpointCodec.pure(records): return {"ok": false, "reason": "invalid_snapshot_segment"}
	var header: Dictionary = records[0]
	if not header.get("metadata") is Dictionary or not header.get("source") is String: return {"ok": false, "reason": "invalid_segment_metadata"}
	if header.get("kind") != "SnapshotHeader" or header.get("schema_version") != "run-snapshot-segment-v1" or not header.get("snapshot") is Dictionary: return {"ok": false, "reason": "invalid_snapshot_segment"}
	if not header.get("segment_id") is String or not TelemetrySchema.safe_id(header.segment_id): return {"ok": false, "reason": "invalid_snapshot_segment"}
	for index: int in range(records.size()):
		if records[index].get("seq") != str(index + 1): return {"ok": false, "reason": "invalid_segment_sequence"}
	var loaded: Dictionary = SNAPSHOT.decode(header.snapshot, expected_manifest)
	if not loaded.ok: return loaded
	var run: RunController = loaded.run
	if header.get("run_id") != run.state.run_id or header.get("config") != RunSnapshot.config(run) or header.get("initial") != RunSnapshot.capture(run): return {"ok": false, "reason": "segment_header_mismatch"}
	var recorder: RunRecorder = RunRecorder.new()
	recorder.source = str(header.get("source", "unknown"))
	recorder.metadata = header.get("metadata", {}).duplicate(true)
	recorder.records.append(header.duplicate(true))
	recorder.checkpoint(run)
	run.recorder = recorder
	var replay: RuleReplay = RuleReplay.new()
	if not replay.verify_snapshot_segment(records, run, recorder): return {"ok": false, "reason": replay.error}
	return {"ok": true, "reason": "", "run": run, "segment_complete": replay.complete, "whole_run_replay": false}

static func _parent_matches(value: Dictionary, row: Dictionary) -> bool:
	return TelemetrySchema.validate(row).is_empty() and row.run_id == value.run_id and row.event_id == value.last_event_id and row.telemetry_seq == value.accepted_seq and RunSnapshot.digest(row) == value.last_event_hash and row.payload.get("snapshot_state_hash") == value.snapshot_state_hash
