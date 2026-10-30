extends CheckpointFiles

## Store-compatible private files, atomically persisted as one IndexedDB value.
## Failed commits restore the last acknowledged file set; no Node or rule state is retained.
const PERSISTENCE: Script = preload("res://services/run_checkpoint/checkpoint_web_persistence.gd")
const SCHEMA: String = "checkpoint-web-files-v1"
const MAX_TOTAL_BYTES: int = 64 * 1024 * 1024
const MAX_FILES: int = 2048
var ready: bool = false
var error: String = "web_storage_not_open"
var _directory: String
var _persistence: PERSISTENCE
var _files: Dictionary[String, PackedByteArray] = {}
var _durable: Dictionary[String, PackedByteArray] = {}
var _dirty: bool = false
var _syncing: bool = false
var _base64: RegEx = RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}\\z")
var _names: RegEx = RegEx.create_from_string("^(primary\\.json|previous\\.json|checkpoint\\.tmp|previous\\.tmp|transaction\\.(tmp|json)|primary\\.(rollback|restore)|previous\\.(rollback|restore)|invalid-[0-9a-f]{64}\\.json(\\.tmp)?|(primary|previous)\\.json\\.corrupt-[0-9a-f]{64}\\.json)$")

func _init(directory: String, persistence: PERSISTENCE = null) -> void:
	_directory = directory.trim_suffix("/")
	_persistence = persistence if persistence != null else PERSISTENCE.new()

func open() -> Dictionary:
	var result: Dictionary = await _persistence.open()
	if not result.ok: return _failed(result.reason)
	if result.data.to_utf8_buffer().size() > MAX_TOTAL_BYTES * 2: return _failed("web_snapshot_size_limit")
	var value: Variant = JSON.parse_string(result.data)
	if not value is Dictionary or value.size() != 2 or value.get("schema") != SCHEMA or not value.get("files") is Dictionary:
		return _failed("web_snapshot_invalid")
	if value.files.size() > MAX_FILES: return _failed("web_snapshot_size_limit")
	var decoded: Dictionary[String, PackedByteArray] = {}
	var total: int = 0
	for name: Variant in value.files:
		if not name is String or _names.search(name) == null or not value.files[name] is String:
			return _failed("web_snapshot_invalid")
		var text: String = value.files[name]
		if text.length() % 4 != 0 or text.length() > MAX_BYTES * 2 or _base64.search(text) == null: return _failed("web_snapshot_invalid")
		var bytes: PackedByteArray = PackedByteArray() if text.is_empty() else Marshalls.base64_to_raw(text)
		if _encode_bytes(bytes) != text or bytes.size() > MAX_BYTES: return _failed("web_snapshot_invalid")
		total += bytes.size()
		if total > MAX_TOTAL_BYTES: return _failed("web_snapshot_size_limit")
		decoded[name] = bytes
	_files = decoded
	_durable = decoded.duplicate(true)
	ready = true
	error = ""
	return {"ok": true, "reason": ""}

func sync() -> Dictionary:
	if not ready: return _failed(error)
	if _syncing: return _failed("web_storage_busy")
	if not _dirty: return {"ok": true, "reason": ""}
	_syncing = true
	var encoded: Dictionary = {}
	for name: String in _files: encoded[name] = _encode_bytes(_files[name])
	var result: Dictionary = await _persistence.save(JSON.stringify({"schema": SCHEMA, "files": encoded}))
	_syncing = false
	if not result.ok:
		_files = _durable.duplicate(true)
		_dirty = false
		if result.reason in ["web_storage_conflict", "web_storage_not_open"]: ready = false
		return _failed(result.reason)
	_durable = _files.duplicate(true)
	_dirty = false
	error = ""
	return {"ok": true, "reason": ""}

func exists(path: String) -> bool:
	var name: String = _name(path)
	return not name.is_empty() and (not ready or _files.has(name))

func read_text(path: String) -> Dictionary:
	if not ready: return {"ok": false, "reason": error, "text": ""}
	var name: String = _name(path)
	if name.is_empty() or not _files.has(name): return {"ok": false, "reason": "missing", "text": ""}
	return {"ok": true, "reason": "", "text": _files[name].get_string_from_utf8()}

func write_text(path: String, text: String) -> Error:
	if not ready or _syncing: return ERR_UNAVAILABLE
	var name: String = _name(path)
	if name.is_empty(): return ERR_INVALID_PARAMETER
	var bytes: PackedByteArray = text.to_utf8_buffer()
	if bytes.size() > MAX_BYTES or (not _files.has(name) and _files.size() >= MAX_FILES): return ERR_OUT_OF_MEMORY
	var total: int = bytes.size()
	for other: String in _files:
		if other != name: total += _files[other].size()
	if total > MAX_TOTAL_BYTES: return ERR_OUT_OF_MEMORY
	_files[name] = bytes
	_dirty = true
	return OK

func replace(source: String, destination: String) -> Error:
	if not ready or _syncing: return ERR_UNAVAILABLE
	var from: String = _name(source)
	var to: String = _name(destination)
	if from.is_empty() or to.is_empty() or not _files.has(from): return ERR_CANT_OPEN
	if from == to: return OK
	_files[to] = _files[from]
	_files.erase(from)
	_dirty = true
	return OK

func fingerprint(path: String) -> String:
	var name: String = _name(path)
	if not ready or name.is_empty() or not _files.has(name): return ""
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(_files[name])
	return hash.finish().hex_encode()

func copy_verified(source: String, destination: String) -> Error:
	if not ready or _syncing: return ERR_UNAVAILABLE
	var from: String = _name(source)
	var to: String = _name(destination)
	if from.is_empty() or to.is_empty() or not _files.has(from): return ERR_CANT_OPEN
	var total: int = _files[from].size()
	for name: String in _files:
		if name != to: total += _files[name].size()
	if total > MAX_TOTAL_BYTES or (not _files.has(to) and _files.size() >= MAX_FILES): return ERR_OUT_OF_MEMORY
	_files[to] = _files[from].duplicate()
	_dirty = true
	return OK

func remove(path: String) -> Error:
	if not ready or _syncing: return ERR_UNAVAILABLE
	var name: String = _name(path)
	if name.is_empty(): return ERR_INVALID_PARAMETER
	_dirty = _files.erase(name) or _dirty
	return OK

func _name(path: String) -> String:
	if not path.begins_with(_directory + "/"): return ""
	var name: String = path.trim_prefix(_directory + "/")
	return name if _names.search(name) != null else ""

func _failed(reason: String) -> Dictionary:
	error = reason
	return {"ok": false, "reason": reason}

static func _encode_bytes(bytes: PackedByteArray) -> String:
	return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)
