class_name RunCheckpointSession
extends RefCounted

## Coordinates validated rule payloads with one synchronous automatic slot.
## No scene takeover, UI, telemetry session creation, or implicit run invalidation.
var _store: CheckpointStore
var _manifest: Dictionary
var rebuild_budget_usec: int = RunCheckpointCodec.REBUILD_BUDGET_USEC
var runtime_only: bool = false
const FLOAT_TRANSPORT: Script = preload("res://services/run_checkpoint/checkpoint_float_transport.gd")
const PACKAGE_SCHEMA: String = "run-checkpoint-package-v3"
const DECIMAL_PACKAGE_SCHEMA: String = "run-checkpoint-package-v2"

func _init(store: CheckpointStore, compatibility: Dictionary) -> void:
	_store = store
	_manifest = compatibility.duplicate(true)

## Validate reconstruction before touching the slot. A failed save preserves the previous pair.
func save(run: RunController) -> Dictionary:
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	return save_encoded(encoded)

## Accepts only a main-thread frozen value; background owners never read an active run.
func save_encoded(encoded: Dictionary) -> Dictionary:
	var prepared: Dictionary = _prepare_save(encoded)
	if not prepared.ok: return prepared
	var verified: Dictionary = RunCheckpointCodec.decode(prepared.payload, _manifest, rebuild_budget_usec, runtime_only)
	if not verified.ok: return verified
	return _commit_save(encoded, prepared.package, verified)

func save_encoded_sliced(encoded: Dictionary, replay_yield: Callable) -> Dictionary:
	var prepared: Dictionary = _prepare_save(encoded)
	if not prepared.ok: return prepared
	var verified: Dictionary = await RunCheckpointCodec.decode_sliced(prepared.payload, _manifest, rebuild_budget_usec, runtime_only, replay_yield)
	if not verified.ok: return verified
	return _commit_save(encoded, prepared.package, verified)

func _prepare_save(encoded: Dictionary) -> Dictionary:
	if not encoded.ok: return encoded
	if encoded.manifest != _manifest: return RunCheckpointCodec.failure("manifest_incompatible")
	var transported: Dictionary = FLOAT_TRANSPORT.encode(encoded.payload)
	if not transported.ok: return RunCheckpointCodec.failure(transported.reason)
	# Binary64 tags avoid relying on the JSON parser's decimal rounding.
	var package: Dictionary = {
		"schema": PACKAGE_SCHEMA, "run_id": encoded.payload.run_id,
		"payload_json": JSON.stringify(transported.data, "", true, true),
		"telemetry": encoded.get("telemetry", {}).duplicate(true) if encoded.get("telemetry", {}) is Dictionary and RunCheckpointCodec.pure(encoded.get("telemetry", {})) else {"status": "invalid_trace"},
	}
	if JSON.stringify(package).to_utf8_buffer().size() > CheckpointFiles.MAX_BYTES - 4096:
		return RunCheckpointCodec.failure("package_size_limit")
	# Verify the actual encoded text through parsing and independent reconstruction before IO.
	var parser: JSON = JSON.new()
	if parser.parse(package.payload_json) != OK or not parser.data is Dictionary:
		return RunCheckpointCodec.failure("invalid_payload_json")
	var roundtrip: Dictionary = FLOAT_TRANSPORT.decode(parser.data)
	if not roundtrip.ok: return RunCheckpointCodec.failure("invalid_payload_json")
	return {"ok": true, "reason": "", "package": package, "payload": roundtrip.data}

func _commit_save(encoded: Dictionary, package: Dictionary, verified: Dictionary) -> Dictionary:
	var opened: Dictionary = _store.begin_run(encoded.payload.run_id)
	if not opened.ok: return opened
	var ticket: int = _store.stage(package, _manifest)
	if ticket == 0: return RunCheckpointCodec.failure("stage_rejected")
	var committed: Dictionary = _store.commit(ticket)
	if not committed.ok: return committed
	return {"ok": true, "reason": "", "generation": str(ticket), "rebuild_usec": verified.rebuild_usec}

## Invalidation and structural fallback are checked by Store before any reconstruction.
## The caller receives a fully separate candidate, never a partial replacement.
func load_candidate() -> Dictionary:
	var loaded: Dictionary = _store.load_latest(_manifest)
	if not loaded.ok: return loaded
	var decoded: Dictionary = _decode_loaded(loaded)
	if decoded.ok or loaded.fallback or not _recoverable_corruption(decoded.reason): return decoded
	var previous: Dictionary = _store.previous_after_rejection(_manifest, loaded.record)
	if not previous.ok:
		decoded["previous_rejection"] = previous.reason
		return decoded
	var recovered: Dictionary = _decode_loaded(previous)
	if not recovered.ok:
		decoded["previous_rejection"] = recovered.reason
		return decoded
	recovered["primary_rejection"] = decoded.reason
	return recovered

func load_candidate_sliced(replay_yield: Callable) -> Dictionary:
	var loaded: Dictionary = _store.load_latest(_manifest)
	if not loaded.ok: return loaded
	var decoded: Dictionary = await _decode_loaded_sliced(loaded, replay_yield)
	if decoded.ok or loaded.fallback or not _recoverable_corruption(decoded.reason): return decoded
	var previous: Dictionary = _store.previous_after_rejection(_manifest, loaded.record)
	if not previous.ok:
		decoded["previous_rejection"] = previous.reason
		return decoded
	var recovered: Dictionary = await _decode_loaded_sliced(previous, replay_yield)
	if not recovered.ok:
		decoded["previous_rejection"] = recovered.reason
		return decoded
	recovered["primary_rejection"] = decoded.reason
	return recovered

func _decode_loaded(loaded: Dictionary) -> Dictionary:
	var unpacked: Dictionary = _unpack_loaded(loaded)
	if not unpacked.ok: return unpacked
	var decoded: Dictionary = RunCheckpointCodec.decode(unpacked.payload, _manifest, rebuild_budget_usec, runtime_only)
	return _finish_loaded(loaded, decoded, unpacked.payload, unpacked.package)

func _decode_loaded_sliced(loaded: Dictionary, replay_yield: Callable) -> Dictionary:
	var unpacked: Dictionary = _unpack_loaded(loaded)
	if not unpacked.ok: return unpacked
	var decoded: Dictionary = await RunCheckpointCodec.decode_sliced(unpacked.payload, _manifest, rebuild_budget_usec, runtime_only, replay_yield)
	return _finish_loaded(loaded, decoded, unpacked.payload, unpacked.package)

func _unpack_loaded(loaded: Dictionary) -> Dictionary:
	var package: Dictionary = loaded.record.payload
	if not package.get("schema") is String: return RunCheckpointCodec.failure("invalid_package")
	if package.schema not in [RunCheckpointCodec.SCHEMA, DECIMAL_PACKAGE_SCHEMA, PACKAGE_SCHEMA]:
		return RunCheckpointCodec.failure("schema_unsupported")
	var expected_size: int = 3 if package.schema == RunCheckpointCodec.SCHEMA else 4
	if package.size() != expected_size or not package.get("payload_json") is String:
		return RunCheckpointCodec.failure("invalid_package")
	if loaded.record.run_id != package.get("run_id"):
		return RunCheckpointCodec.failure("container_identity_mismatch")
	var parser: JSON = JSON.new()
	if parser.parse(package.payload_json) != OK or not parser.data is Dictionary:
		return RunCheckpointCodec.failure("invalid_payload_json")
	if package.schema == PACKAGE_SCHEMA:
		var transported: Dictionary = FLOAT_TRANSPORT.decode(parser.data)
		if not transported.ok: return RunCheckpointCodec.failure("invalid_payload_json")
		parser.data = transported.data
	if parser.data.get("run_id") != package.run_id:
		return RunCheckpointCodec.failure("payload_identity_mismatch")
	return {"ok": true, "reason": "", "payload": parser.data, "package": package}

func _finish_loaded(loaded: Dictionary, decoded: Dictionary, payload: Dictionary, package: Dictionary) -> Dictionary:
	if not decoded.ok: return decoded
	decoded["generation"] = loaded.record.generation
	decoded["fallback"] = loaded.fallback
	decoded["recovered_write"] = loaded.recovered_write
	decoded["resume_context"] = {"checkpoint_id": loaded.record.run_id + ":" + loaded.record.generation + ":" + payload.state_hash, "generation": loaded.record.generation, "record_seq": payload.record_seq, "state_hash": payload.state_hash, "trace": package.get("telemetry", {}).duplicate(true) if package.get("telemetry", {}) is Dictionary else {"status": "invalid_trace"}}
	return decoded

## Unknown protocols/configurations, unsupported contexts and cost limits are not corruption repair.
static func _recoverable_corruption(reason: String) -> bool:
	if reason.begins_with("missing_payload_field:") or reason.begins_with("rebuild_failed:seq="): return true
	if reason in ["rebuild_failed:invalid_random_streams", "rebuild_failed:invalid_master_seed", "rebuild_failed:initial_state_mismatch", "rebuild_failed:initial_random_mismatch"]: return true
	return reason in ["invalid_package", "invalid_payload_json", "container_identity_mismatch", "payload_identity_mismatch", "invalid_payload", "noncanonical_payload", "invalid_run_id", "invalid_master_seed", "invalid_endpoint", "endpoint_hash_mismatch", "invalid_safe_point", "prefix_sequence_mismatch", "invalid_record_sequence", "invalid_record_kind", "invalid_prefix_header", "identity_mismatch", "invalid_command", "incomplete_prefix", "endpoint_mismatch", "offer_cache_mismatch", "safe_point_mismatch"]
