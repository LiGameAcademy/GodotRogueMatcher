extends SceneTree

## Profiles the real previously measured checkpoints without changing their files.
var _results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the isolated benchmark directory")
		quit(2)
		return
	for name: String in DirAccess.get_directories_at(args[0]):
		var directory: String = args[0].path_join(name)
		if not FileAccess.file_exists(directory.path_join("primary.json")): continue
		var row: Dictionary = _profile(directory)
		_results.append(row)
		var output: FileAccess = FileAccess.open("res://.godot/checkpoint-profile.json", FileAccess.WRITE)
		output.store_string(JSON.stringify({"engine": Engine.get_version_info(), "results": _results}, "\t", true, true))
		output.close()
		print("CHECKPOINT_PROFILE " + JSON.stringify(row))
	quit()

func _profile(directory: String) -> Dictionary:
	var wall_started: int = Time.get_ticks_usec()
	var store: CheckpointStore = CheckpointStore.new(directory)
	var started: int = Time.get_ticks_usec()
	var metadata: Dictionary = store.inspect_latest()
	var discovery_usec: int = Time.get_ticks_usec() - started
	if not metadata.ok: return {"ok": false, "reason": metadata.reason}
	started = Time.get_ticks_usec()
	var loaded: Dictionary = store.load_latest(metadata.manifest)
	var container_read_verify_usec: int = Time.get_ticks_usec() - started
	if not loaded.ok: return {"ok": false, "reason": loaded.reason}
	started = Time.get_ticks_usec()
	var payload: Dictionary = JSON.parse_string(loaded.record.payload.payload_json)
	if loaded.record.payload.schema == RunCheckpointSession.PACKAGE_SCHEMA:
		var transported: Dictionary = preload("res://services/run_checkpoint/checkpoint_float_transport.gd").decode(payload)
		if not transported.ok: return {"ok": false, "reason": "invalid_payload_json"}
		payload = transported.data
	var payload_parse_usec: int = Time.get_ticks_usec() - started
	var decoded: Dictionary = RunCheckpointCodec.decode(payload, metadata.manifest, 10000000)
	if not decoded.ok: return {"ok": false, "reason": decoded.reason, "timing": decoded.get("timing")}
	started = Time.get_ticks_usec()
	var encoded: Dictionary = RunCheckpointCodec.encode(decoded.run)
	var freeze_encode_usec: int = Time.get_ticks_usec() - started
	if not encoded.ok: return {"ok": false, "reason": encoded.reason}
	started = Time.get_ticks_usec()
	var frozen: Dictionary = RunCheckpointCodec.freeze(decoded.run)
	var desktop_freeze_usec: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var serialized: String = JSON.stringify(encoded.payload, "", true, true)
	var serialization_usec: int = Time.get_ticks_usec() - started
	var verified: Dictionary = RunCheckpointCodec.decode(encoded.payload, metadata.manifest, 10000000)
	var fresh: CheckpointStore = CheckpointStore.new("user://checkpoint-profile/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var package: Dictionary = {"schema": RunCheckpointCodec.SCHEMA, "run_id": payload.run_id, "payload_json": serialized}
	started = Time.get_ticks_usec()
	var opened: Dictionary = fresh.begin_run(payload.run_id)
	var committed: Dictionary = fresh.commit(fresh.stage(package, metadata.manifest)) if opened.ok else opened
	var container_commit_readback_usec: int = Time.get_ticks_usec() - started
	return {
		"ok": committed.ok and verified.ok, "source": "actual_normal_rules_checkpoint",
		"mode": metadata.manifest.mode_id, "seed": payload.master_seed, "rules": metadata.manifest.rules_version,
		"actions": payload.state.action, "records": payload.records.size(), "payload_bytes": serialized.to_utf8_buffer().size(),
		"on_main_thread": Thread.is_main_thread(), "discovery_usec": discovery_usec,
		"container_read_verify_usec": container_read_verify_usec, "payload_parse_usec": payload_parse_usec,
		"load_rebuild_usec": decoded.rebuild_usec, "load_timing": decoded.timing,
		"freeze_encode_usec": freeze_encode_usec, "serialization_usec": serialization_usec,
		"desktop_freeze_usec": desktop_freeze_usec, "frozen_matches_encoded": frozen.payload == encoded.payload,
		"save_preflight_rebuild_usec": verified.get("rebuild_usec"), "save_timing": verified.get("timing"),
		"container_commit_readback_usec": container_commit_readback_usec,
		"profile_total_usec": Time.get_ticks_usec() - wall_started,
		"note": "profiling intentionally performs separate rebuilds to measure phases; these are not additional required UI validations",
	}
