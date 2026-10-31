extends RefCounted

## Parses and verifies Store containers; sliced IO keeps the same validation and failure order.
const INVALID_FORMAT: String = "checkpoint-invalid-v1"
const TRANSACTION_FORMAT: String = "checkpoint-transaction-v1"

static func decode(text: String, format: String) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return _failure("malformed_json")
	return _verify(parser.data, format)

static func _verify(value: Variant, format: String) -> Dictionary:
	if not value is Dictionary: return _failure("malformed_json")
	var record: Dictionary = value as Dictionary
	if not record.get("format") is String: return _failure("invalid_envelope")
	if record.format != format: return _failure("schema_unsupported")
	if not record.get("digest") is String or not record.get("run_id") is String or not CheckpointStore._valid_id(record.run_id): return _failure("invalid_envelope")
	var content: Dictionary = record.duplicate(true)
	content.erase("digest")
	if record.digest != CheckpointStore._json(content).sha256_text(): return _failure("checksum_mismatch")
	if format == INVALID_FORMAT:
		if record.size() != 4 or record.get("reason") not in ["restart", "terminal", "abandoned"]: return _failure("invalid_marker")
	else:
		if record.size() != 6 or not record.get("generation") is String: return _failure("invalid_envelope")
		var generation: String = record.generation
		if not generation.is_valid_int() or str(generation.to_int()) != generation or generation.to_int() <= 0: return _failure("invalid_generation")
		if format == TRANSACTION_FORMAT:
			for key: String in ["primary_hash", "previous_hash"]:
				if not record.get(key) is String: return _failure("invalid_journal")
				if not record[key].is_empty() and RegEx.create_from_string("^[0-9a-f]{64}$").search(record[key]) == null: return _failure("invalid_journal")
		else:
			if not record.get("manifest") is Dictionary or not CheckpointStore._manifest_valid(record.manifest): return _failure("invalid_manifest")
			if not record.get("payload") is Dictionary or not CheckpointStore._pure(record.payload): return _failure("invalid_payload")
	return {"ok": true, "reason": "", "record": record}

static func decode_sliced(text: String, format: String, frame_yield: Callable) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return _failure("malformed_json")
	var parse_usec: int = Time.get_ticks_usec() - started
	await frame_yield.call()
	started = Time.get_ticks_usec()
	var result: Dictionary = _verify(parser.data, format)
	result["verify_slice_usec"] = Time.get_ticks_usec() - started
	result["largest_slice_usec"] = maxi(parse_usec, result.verify_slice_usec)
	return result

static func write_verified_sliced(files: CheckpointFiles, path: String, record: Dictionary, format: String, frame_yield: Callable) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var text: String = CheckpointStore._json(record)
	var largest: int = Time.get_ticks_usec() - started
	await frame_yield.call()
	started = Time.get_ticks_usec()
	if files.write_text(path, text) != OK: return _failure("temporary_write_failed:" + path.get_file())
	largest = maxi(largest, Time.get_ticks_usec() - started)
	await frame_yield.call()
	started = Time.get_ticks_usec()
	var readback: Dictionary = files.read_text(path)
	if not readback.ok: return _failure("temporary_read_failed:" + path.get_file())
	largest = maxi(largest, Time.get_ticks_usec() - started)
	await frame_yield.call()
	var decoded: Dictionary = await decode_sliced(readback.text, format, frame_yield)
	started = Time.get_ticks_usec()
	if not decoded.ok or decoded.record != record: return _failure("temporary_verify_failed:" + path.get_file())
	largest = maxi(largest, decoded.verify_slice_usec + Time.get_ticks_usec() - started)
	return {"ok": true, "reason": "", "largest_slice_usec": maxi(largest, decoded.largest_slice_usec)}

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "record": {}}
