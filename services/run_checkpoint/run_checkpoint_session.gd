class_name RunCheckpointSession
extends RefCounted

## Coordinates validated rule payloads with one synchronous automatic slot.
## No scene takeover, UI, telemetry session creation, or implicit run invalidation.
var _store: CheckpointStore
var _manifest: Dictionary

func _init(store: CheckpointStore, compatibility: Dictionary) -> void:
	_store = store
	_manifest = compatibility.duplicate(true)

## Validate reconstruction before touching the slot. A failed save preserves the previous pair.
func save(run: RunController) -> Dictionary:
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	if not encoded.ok: return encoded
	if encoded.manifest != _manifest: return RunCheckpointCodec.failure("manifest_incompatible")
	var verified: Dictionary = RunCheckpointCodec.decode(encoded.payload, _manifest)
	if not verified.ok: return verified
	# Preserve binary64 weights exactly without changing the existing Store digest protocol.
	var package: Dictionary = {
		"schema": RunCheckpointCodec.SCHEMA, "run_id": run.state.run_id,
		"payload_json": JSON.stringify(encoded.payload, "", true, true),
	}
	if JSON.stringify(package).to_utf8_buffer().size() > CheckpointFiles.MAX_BYTES - 4096:
		return RunCheckpointCodec.failure("package_size_limit")
	var opened: Dictionary = _store.begin_run(run.state.run_id)
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
	var package: Dictionary = loaded.record.payload
	if package.size() != 3 or package.get("schema") != RunCheckpointCodec.SCHEMA or not package.get("payload_json") is String:
		return RunCheckpointCodec.failure("invalid_package")
	if loaded.record.run_id != package.get("run_id"):
		return RunCheckpointCodec.failure("container_identity_mismatch")
	var parser: JSON = JSON.new()
	if parser.parse(package.payload_json) != OK or not parser.data is Dictionary:
		return RunCheckpointCodec.failure("invalid_payload_json")
	if parser.data.get("run_id") != package.run_id:
		return RunCheckpointCodec.failure("payload_identity_mismatch")
	var decoded: Dictionary = RunCheckpointCodec.decode(parser.data, _manifest)
	if not decoded.ok: return decoded
	decoded["generation"] = loaded.record.generation
	decoded["fallback"] = loaded.fallback
	decoded["recovered_write"] = loaded.recovered_write
	return decoded
