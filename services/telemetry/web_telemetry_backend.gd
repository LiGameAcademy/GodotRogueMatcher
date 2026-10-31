extends RefCounted

## Serial append queue and acknowledged browser file view; never touches a rule run.
signal acknowledged(name: String, sequence: int)
signal changed
const PERSISTENCE: Script = preload("res://services/telemetry/web_telemetry_persistence.gd")
const MAX_QUEUE_BYTES: int = 4 * 1024 * 1024
const MAX_FILE_BYTES: int = 16 * 1024 * 1024
const MAX_TOTAL_BYTES: int = 64 * 1024 * 1024
const MAX_FILES: int = 2048
var ready: bool = false
var error: String = ""
var writing: bool = false
var _opening: bool = false
var _snapshotting: bool = false
var _persistence: PERSISTENCE
var _files: Dictionary[String, Dictionary] = {}
var _reserved: Dictionary[String, bool] = {}
var _pending: Dictionary[String, PackedByteArray] = {}
var _sequences: Dictionary[String, int] = {}
var _accepted: Dictionary[String, int] = {}
var _persisted: Dictionary[String, int] = {}
var _pending_bytes: int = 0
var _inflight: Dictionary = {}
var _names: RegEx = RegEx.create_from_string("^(telemetry|sessions|run_records)/[A-Za-z0-9][A-Za-z0-9_.-]{0,180}\\.jsonl\\z")

func _init(persistence: PERSISTENCE = null) -> void:
	_persistence = persistence if persistence != null else PERSISTENCE.new()

func open() -> Dictionary:
	if ready or writing or _opening: return {"ok": false, "reason": "web_telemetry_busy"}
	_opening = true
	var loaded: Dictionary = await _persistence.open()
	if not loaded.ok: return _failed(loaded.reason)
	var parsed: Dictionary = _parse_snapshot(loaded.data)
	if not parsed.ok: return parsed
	var files: Dictionary[String, Dictionary] = parsed.files
	_files = files
	ready = true
	_opening = false
	return {"ok": true, "reason": ""}

## A new segment cannot append to an existing identity, even after a refresh.
func reserve(name: String) -> bool:
	if not ready or not error.is_empty() or not _valid_name(name) or _files.has(name) or _reserved.has(name): return false
	var count: int = _files.size()
	for reserved: String in _reserved:
		if not _files.has(reserved): count += 1
	if count >= MAX_FILES: return false
	_reserved[name] = true
	_accepted[name] = 0
	return true

func append(name: String, text: String, sequence: int) -> bool:
	if not ready or not error.is_empty() or not _reserved.has(name) or not text.ends_with("\n") or sequence <= _accepted.get(name, 0): return false
	var bytes: PackedByteArray = text.to_utf8_buffer()
	var inflight_bytes: int = int(_inflight.get("bytes", 0))
	if bytes.size() + _pending_bytes + inflight_bytes > MAX_QUEUE_BYTES:
		_failed("web_telemetry_queue_limit")
		return false
	var queued: PackedByteArray = _pending.get(name, PackedByteArray())
	queued.append_array(bytes)
	_pending[name] = queued
	_sequences[name] = sequence
	_accepted[name] = sequence
	_pending_bytes += bytes.size()
	if not writing: _drain.call_deferred()
	return true

func files() -> Dictionary[String, String]:
	var snapshot: Dictionary[String, String] = {}
	for name: String in _files: snapshot[name] = _files[name].text
	return snapshot

func pending() -> bool:
	return writing or not _pending.is_empty()

func persisted_sequence(name: String) -> int:
	return _persisted.get(name, 0)

## Export reads the actual database, including other tabs, without replacing the writer cache.
func snapshot() -> Dictionary:
	if not ready or writing or _snapshotting: return {"ok": false, "reason": "web_telemetry_busy"}
	_snapshotting = true
	var loaded: Dictionary = await _persistence.snapshot()
	var parsed: Dictionary = _parse_snapshot(loaded.data) if loaded.ok else _failed(loaded.reason)
	_snapshotting = false
	if not _pending.is_empty() and error.is_empty(): _drain.call_deferred()
	if not parsed.ok: return parsed
	var snapshot_files: Dictionary[String, String] = {}
	for name: String in parsed.files: snapshot_files[name] = parsed.files[name].text
	return {"ok": true, "reason": "", "files": snapshot_files}

func _drain() -> void:
	if writing or _snapshotting or not ready or not error.is_empty(): return
	writing = true
	while not _pending.is_empty() and error.is_empty():
		var name: String = _pending.keys()[0]
		var bytes: PackedByteArray = _pending[name]
		var sequence: int = _sequences[name]
		_pending.erase(name)
		_sequences.erase(name)
		_pending_bytes -= bytes.size()
		var text: String = bytes.get_string_from_utf8()
		var revision: int = int(_files.get(name, {}).get("revision", 0))
		_inflight = {"name": name, "text": text, "bytes": bytes.size(), "sequence": sequence}
		var written: Dictionary = await _persistence.append(name, revision, text)
		if not written.ok:
			_failed(written.reason)
			break
		var previous: String = String(_files.get(name, {}).get("text", ""))
		_files[name] = {"revision": revision + 1, "text": previous + text}
		_persisted[name] = sequence
		_inflight.clear()
		acknowledged.emit(name, sequence)
		changed.emit()
	writing = false
	changed.emit()

func _parse_snapshot(data: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(data)
	if not parsed is Dictionary or parsed.size() > MAX_FILES: return _failed("web_telemetry_snapshot_invalid")
	var files: Dictionary[String, Dictionary] = {}
	var total: int = 0
	for name: Variant in parsed:
		if not name is String or not _valid_name(name): return _failed("web_telemetry_snapshot_invalid")
		var row: Variant = parsed[name]
		if not row is Dictionary or row.size() != 3 or row.get("schema") != "web-collection-file-v1" or not row.get("text") is String:
			return _failed("web_telemetry_snapshot_invalid")
		if not _valid_revision(row.get("revision")) or not row.text.ends_with("\n"):
			return _failed("web_telemetry_snapshot_invalid")
		var count: int = row.text.to_utf8_buffer().size()
		if count > MAX_FILE_BYTES: return _failed("web_telemetry_size_limit")
		total += count
		if total > MAX_TOTAL_BYTES: return _failed("web_telemetry_size_limit")
		files[name] = {"revision": int(row.revision), "text": String(row.text)}
	return {"ok": true, "reason": "", "files": files}

func _valid_name(name: String) -> bool:
	return not name.contains("..") and _names.search(name) != null

func _valid_revision(value: Variant) -> bool:
	if not value is float and not value is int: return false
	var number: float = float(value)
	return is_finite(number) and number >= 1.0 and number <= 9007199254740991.0 and floor(number) == number

func _failed(reason: String) -> Dictionary:
	_opening = false
	if error.is_empty(): error = reason
	changed.emit()
	return {"ok": false, "reason": reason}
