extends RefCounted

## Owns a browser database connection and keeps its callback alive until completion.
signal completed(result: Dictionary)

const TEXT: Script = preload("res://services/run_checkpoint/checkpoint_bridge_text.gd")

var _api: JavaScriptObject
var _callback: JavaScriptObject
var _busy: bool = false

func open() -> Dictionary:
	if not OS.has_feature("web"): return _failure("web_backend_required")
	var source: String = FileAccess.get_file_as_string("res://services/run_checkpoint/checkpoint_web_storage.js")
	if source.is_empty(): return _failure("web_backend_missing")
	JavaScriptBridge.eval(source, true)
	var entry: JavaScriptObject = JavaScriptBridge.get_interface("SkillLinesCheckpointStorage")
	if entry == null: return _failure("web_backend_missing")
	_api = entry.create()
	return await _request("open", "")

func save(data: String) -> Dictionary:
	if _api == null: return _failure("web_storage_not_open")
	return await _request("save", data)

func _request(method: String, data: String) -> Dictionary:
	if _busy: return _failure("web_storage_busy")
	_busy = true
	_callback = JavaScriptBridge.create_callback(_receive)
	if method == "open": _api.openChunked(_callback)
	else: _api.save(data, _callback)
	# The JS bridge always defers even immediate errors, so this await cannot miss completion.
	var result: Dictionary = await completed
	if method == "open" and result.ok:
		result = await TEXT.receive(result.data, _read_chunk, _finish_chunks, _yield_bridge)
	_callback = null
	_busy = false
	return result

func _read_chunk(id: String, index: int) -> Variant:
	return _api.readOpenChunk(id, index)

func _finish_chunks(id: String, index: int, cancel: bool) -> bool:
	if cancel:
		_api.cancelOpen()
		return false
	return bool(_api.finishOpen(id, index))

func _yield_bridge() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _receive(arguments: Array) -> void:
	# Keep the opaque file-map text out of a second full JSON envelope roundtrip.
	if arguments.size() != 3 or not arguments[0] is bool or not arguments[1] is String or not arguments[2] is String:
		completed.emit(_failure("web_backend_response_invalid"))
		return
	completed.emit({"ok": arguments[0], "reason": arguments[1], "data": arguments[2]})

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "data": ""}
