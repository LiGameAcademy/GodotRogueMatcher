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
var _opening: bool = false
var _frame_yield: Callable
var _base64: RegEx = RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}\\z")
var _names: RegEx = RegEx.create_from_string("^(primary\\.json|previous\\.json|checkpoint\\.tmp|previous\\.tmp|transaction\\.(tmp|json)|primary\\.(rollback|restore)|previous\\.(rollback|restore)|invalid-[0-9a-f]{64}\\.json(\\.tmp)?|(primary|previous)\\.json\\.corrupt-[0-9a-f]{64}\\.json)$")

func _init(directory: String, persistence: PERSISTENCE = null, frame_yield: Callable = Callable()) -> void:
	_directory = directory.trim_suffix("/")
	_persistence = persistence if persistence != null else PERSISTENCE.new()
	_frame_yield = frame_yield

func open() -> Dictionary:
	if _opening or _syncing or _dirty: return _failed("web_storage_busy")
	_opening = true
	ready = false
	var result: Dictionary = await _open()
	_opening = false
	return result

func _open() -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = await _persistence.open()
	if not result.ok: return _failed(result.reason)
	var timing: Dictionary = {"database_read_elapsed_usec": Time.get_ticks_usec() - started, "files": []}
	await _yield_io()
	started = Time.get_ticks_usec()
	if result.data.to_utf8_buffer().size() > MAX_TOTAL_BYTES * 2: return _failed("web_snapshot_size_limit")
	timing["snapshot_utf8_usec"] = Time.get_ticks_usec() - started
	await _yield_io()
	started = Time.get_ticks_usec()
	var value: Variant = JSON.parse_string(result.data)
	timing["snapshot_parse_usec"] = Time.get_ticks_usec() - started
	await _yield_io()
	if not value is Dictionary or value.size() != 2 or value.get("schema") != SCHEMA or not value.get("files") is Dictionary:
		return _failed("web_snapshot_invalid")
	if value.files.size() > MAX_FILES: return _failed("web_snapshot_size_limit")
	var decoded: Dictionary[String, PackedByteArray] = {}
	var total: int = 0
	for name: Variant in value.files:
		started = Time.get_ticks_usec()
		if not name is String or _names.search(name) == null or not value.files[name] is String:
			return _failed("web_snapshot_invalid")
		var text: String = value.files[name]
		if text.length() % 4 != 0 or text.length() > MAX_BYTES * 2 or _base64.search(text) == null: return _failed("web_snapshot_invalid")
		var file_timing: Dictionary = {"name": name, "base64_validation_usec": Time.get_ticks_usec() - started}
		started = Time.get_ticks_usec()
		var bytes: PackedByteArray = PackedByteArray() if text.is_empty() else Marshalls.base64_to_raw(text)
		file_timing["base64_decode_usec"] = Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		if _encode_bytes(bytes) != text or bytes.size() > MAX_BYTES: return _failed("web_snapshot_invalid")
		file_timing["canonical_encode_compare_usec"] = Time.get_ticks_usec() - started
		file_timing["bytes"] = bytes.size()
		timing.files.append(file_timing)
		total += bytes.size()
		if total > MAX_TOTAL_BYTES: return _failed("web_snapshot_size_limit")
		decoded[name] = bytes
		await _yield_io()
	started = Time.get_ticks_usec()
	_files = decoded
	_durable = decoded.duplicate(true)
	timing["snapshot_copy_usec"] = Time.get_ticks_usec() - started
	ready = true
	error = ""
	return {"ok": true, "reason": "", "timing": timing}

func sync() -> Dictionary:
	if _opening: return _failed("web_storage_busy")
	if not ready: return _failed(error)
	if _syncing: return _failed("web_storage_busy")
	if not _dirty: return {"ok": true, "reason": ""}
	_syncing = true
	var encoding_started: int = Time.get_ticks_usec()
	var encode_usec: int = 0
	var largest: int = 0
	var encoded: Dictionary = {}
	for name: String in _files:
		var file_started: int = Time.get_ticks_usec()
		encoded[name] = _encode_bytes(_files[name])
		var file_usec: int = Time.get_ticks_usec() - file_started
		encode_usec += file_usec
		largest = maxi(largest, file_usec)
		await _yield_io()
	var started: int = Time.get_ticks_usec()
	var payload: String = JSON.stringify({"schema": SCHEMA, "files": encoded})
	var serialize_usec: int = Time.get_ticks_usec() - started
	encode_usec += serialize_usec
	largest = maxi(largest, serialize_usec)
	var encode_elapsed: int = Time.get_ticks_usec() - encoding_started
	await _yield_io()
	var result: Dictionary = await _persistence.save(payload)
	_syncing = false
	if not result.ok:
		_files = _durable.duplicate(true)
		_dirty = false
		if result.reason in ["web_storage_conflict", "web_storage_not_open"]: ready = false
		return _failed(result.reason)
	_durable = _files.duplicate(true)
	_dirty = false
	error = ""
	return {"ok": true, "reason": "", "timing": {"filemap_encode_usec": encode_usec, "filemap_encode_elapsed_usec": encode_elapsed, "largest_filemap_slice_usec": largest}}

func exists(path: String) -> bool:
	var name: String = _name(path)
	return not name.is_empty() and (not ready or _opening or _files.has(name))

func read_text(path: String) -> Dictionary:
	if _opening: return {"ok": false, "reason": "web_storage_busy", "text": ""}
	if not ready: return {"ok": false, "reason": error, "text": ""}
	var name: String = _name(path)
	if name.is_empty() or not _files.has(name): return {"ok": false, "reason": "missing", "text": ""}
	return {"ok": true, "reason": "", "text": _files[name].get_string_from_utf8()}

func write_text(path: String, text: String) -> Error:
	if not ready or _opening or _syncing: return ERR_UNAVAILABLE
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
	if not ready or _opening or _syncing: return ERR_UNAVAILABLE
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
	if not ready or _opening or name.is_empty() or not _files.has(name): return ""
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(_files[name])
	return hash.finish().hex_encode()

func copy_verified(source: String, destination: String) -> Error:
	if not ready or _opening or _syncing: return ERR_UNAVAILABLE
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
	if not ready or _opening or _syncing: return ERR_UNAVAILABLE
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

func _yield_io() -> void:
	if _frame_yield.is_valid():
		await _frame_yield.call()
	elif OS.has_feature("web"):
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		await tree.process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
