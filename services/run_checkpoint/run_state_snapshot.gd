extends RefCounted

## Experimental current-state safe-point checkpoint, separate from the legacy prefix reader.
## Uses CoreSystem's pure JSON serializer; Store still owns generations, backups and IO ack.
const RESTORE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const V: Script = preload("res://services/run_checkpoint/snapshot_values.gd")
const FLOATS: Script = preload("res://services/run_checkpoint/checkpoint_float_transport.gd")
const JSON_SERIALIZER: Script = preload("res://addons/godot_core_system/source/utils/io_strategies/serialization/json_serialization_strategy.gd")
const SCHEMA: String = "run-state-snapshot-safe-v2"
const PACKAGE_SCHEMA: String = "run-state-snapshot-package-v2"
const MAX_BYTES: int = 1024 * 1024

static func manifest(run: RunController) -> Dictionary:
	var value: Dictionary = RunCheckpointCodec.manifest(run)
	value.save_schema_version = SCHEMA
	return value

## The automatic-save caller may supply the projection and hash it just read to deduplicate.
static func freeze(run: RunController, state: Dictionary = {}, state_hash: String = "") -> Dictionary:
	if run == null or run.initialization != "normal" or not run.prototype_profile.is_empty(): return _failure("snapshot_normal_run_required")
	if run.state.phase not in [RunState.Phase.INPUT, RunState.Phase.REWARDS]: return _failure("snapshot_unsafe_phase")
	var reason: String = RunCheckpointCodec.safety_error(run)
	if not reason.is_empty(): return _failure(reason)
	if state.is_empty(): state = RESTORE.project(run)
	if state_hash.is_empty(): state_hash = RunSnapshot.digest(state)
	var payload: Dictionary = {
		"schema": SCHEMA, "run_id": run.state.run_id, "master_seed": str(run.state.random_streams.master_seed),
		"board": {"columns": str(run.state.rules.state.columns), "rows": str(run.state.rules.state.rows), "match_count": str(run.state.rules.minimum_match_count)},
		"stage_config": {} if not run.state.stage.enabled() else RunSnapshot.resource_fields(run.state.stage.config),
		"manifest": manifest(run), "state": state, "state_hash": state_hash,
	}
	return {"ok": true, "reason": "", "payload": payload, "manifest": payload.manifest}

static func decode(payload: Variant, expected_manifest: Dictionary) -> Dictionary:
	if not V.keys(payload, PackedStringArray(["schema", "run_id", "master_seed", "board", "stage_config", "manifest", "state", "state_hash"])): return _failure("invalid_snapshot")
	if not RunCheckpointCodec.pure(payload) or JSON.stringify(payload).to_utf8_buffer().size() > MAX_BYTES: return _failure("invalid_snapshot_value_or_size")
	if payload.schema != SCHEMA: return _failure("snapshot_schema_unsupported")
	if not payload.run_id is String or not CheckpointStore._valid_id(payload.run_id) or not V.integer(payload.master_seed, 0): return _failure("invalid_snapshot_identity")
	if not payload.state is Dictionary or not payload.board is Dictionary or not payload.manifest is Dictionary: return _failure("invalid_snapshot")
	if payload.manifest != expected_manifest: return _failure("manifest_incompatible")
	if not payload.state_hash is String or RunSnapshot.digest(payload.state) != payload.state_hash: return _failure("snapshot_hash_mismatch")
	if not payload.stage_config is Dictionary: return _failure("snapshot_state_invalid")
	var stage: StageConfig = null
	if not payload.stage_config.is_empty():
		stage = StageConfig.from_record(payload.stage_config)
		if stage == null: return _failure("snapshot_state_invalid")
	var restored: Dictionary = RESTORE.restore(payload.state, String(payload.master_seed).to_int(), payload.run_id, payload.board, stage)
	if not restored.ok: return restored
	var run: RunController = restored.run
	if manifest(run) != expected_manifest: return _failure("manifest_incompatible")
	return {"ok": true, "reason": "", "run": run}

static func serialize(payload: Dictionary) -> Dictionary:
	var transported: Dictionary = FLOATS.encode(payload)
	if not transported.ok: return transported
	var serializer: JSON_SERIALIZER = JSON_SERIALIZER.new()
	serializer.indent = ""
	serializer.sort_keys = true
	var bytes: Variant = serializer.serialize(transported.data)
	if not bytes is PackedByteArray or bytes.size() > MAX_BYTES: return _failure("snapshot_size_or_serialize_failed")
	return {"ok": true, "reason": "", "bytes": bytes}

static func deserialize(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_BYTES: return _failure("snapshot_size_limit")
	var serializer: JSON_SERIALIZER = JSON_SERIALIZER.new()
	var parsed: Variant = serializer.deserialize(bytes)
	if not parsed is Dictionary: return _failure("snapshot_json_invalid")
	var decoded: Dictionary = FLOATS.decode(parsed)
	if decoded.ok and not decoded.data is Dictionary: return _failure("snapshot_json_invalid")
	return decoded

static func save(store: CheckpointStore, run: RunController, trace: Dictionary = {}) -> Dictionary:
	var frozen: Dictionary = freeze(run)
	return await save_frozen(store, frozen, trace)

## Frozen values only: workers never read the active rule graph. Job owns Web sync when false.
static func save_frozen(store: CheckpointStore, frozen: Dictionary, trace: Dictionary = {}, sync_storage: bool = true) -> Dictionary:
	if not frozen.ok: return frozen
	var encoded: Dictionary = serialize(frozen.payload)
	if not encoded.ok: return encoded
	var roundtrip: Dictionary = deserialize(encoded.bytes)
	if not roundtrip.ok: return roundtrip
	var checked: Dictionary = decode(roundtrip.data, frozen.payload.manifest)
	if not checked.ok: return checked
	var old: Dictionary = store.inspect_latest()
	if old.ok and old.manifest.get("save_schema_version") != SCHEMA: return _failure("snapshot_slot_requires_migration")
	var started: Dictionary = store.begin_run(frozen.payload.run_id)
	if not started.ok: return started
	var ticket: int = store.stage({"schema": PACKAGE_SCHEMA, "run_id": frozen.payload.run_id, "snapshot_json": encoded.bytes.get_string_from_utf8(), "trace": trace.duplicate(true) if RunCheckpointCodec.pure(trace) and JSON.stringify(trace).length() <= 2048 else {}}, frozen.payload.manifest)
	if ticket == 0: return _failure("snapshot_stage_rejected")
	var committed: Dictionary = store.commit(ticket)
	if not committed.ok: return committed
	if sync_storage:
		var synced: Dictionary = await store.sync()
		if not synced.ok: return synced
	return {"ok": true, "reason": "", "snapshot_bytes": encoded.bytes.size(), "generation": str(ticket)}

static func load(store: CheckpointStore, expected_manifest: Dictionary) -> Dictionary:
	var loaded: Dictionary = store.load_latest(expected_manifest)
	if not loaded.ok: return loaded
	var decoded: Dictionary = _decode_record(loaded.record, expected_manifest)
	if decoded.ok:
		decoded["fallback"] = loaded.fallback
		return decoded
	var recoverable: PackedStringArray = PackedStringArray(["snapshot_json_invalid", "snapshot_hash_mismatch", "snapshot_state_invalid", "snapshot_scalars_invalid", "snapshot_maps_invalid", "snapshot_skills_invalid", "snapshot_innate_invalid", "snapshot_spawning_invalid", "snapshot_roots_invalid", "snapshot_unsettled_roots"])
	if loaded.fallback or (not recoverable.has(decoded.reason) and not String(decoded.reason).begins_with("snapshot_roundtrip:")): return decoded
	var previous: Dictionary = store.previous_after_rejection(expected_manifest, loaded.record)
	if not previous.ok: return decoded
	var recovered: Dictionary = _decode_record(previous.record, expected_manifest)
	if not recovered.ok: return decoded
	recovered["fallback"] = true
	recovered["primary_rejection"] = decoded.reason
	return recovered

static func _decode_record(record: Dictionary, expected_manifest: Dictionary) -> Dictionary:
	var package: Dictionary = record.payload
	if not V.keys(package, PackedStringArray(["schema", "run_id", "snapshot_json", "trace"])) and not V.keys(package, PackedStringArray(["schema", "run_id", "snapshot_json"])):
		return _failure("snapshot_package_unsupported")
	if package.schema != PACKAGE_SCHEMA or not package.snapshot_json is String:
		return _failure("snapshot_package_unsupported")
	if package.run_id != record.run_id: return _failure("snapshot_identity_mismatch")
	var transported: Dictionary = deserialize(package.snapshot_json.to_utf8_buffer())
	if not transported.ok: return transported
	if transported.data.get("run_id") != package.run_id: return _failure("snapshot_identity_mismatch")
	var restored: Dictionary = decode(transported.data, expected_manifest)
	if restored.ok:
		restored["trace"] = package.trace.duplicate(true) if package.get("trace") is Dictionary else {}
		restored["resume_context"] = {"protocol": "snapshot-command-segment-v1", "checkpoint_id": record.run_id + ":" + record.generation + ":" + transported.data.state_hash, "generation": record.generation, "state_hash": transported.data.state_hash, "trace": restored.trace}
	return restored

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
