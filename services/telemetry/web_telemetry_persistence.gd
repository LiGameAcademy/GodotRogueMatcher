extends RefCounted

## Browser callback owner. Acknowledgement comes only from the IndexedDB transaction.
signal completed(result: Dictionary)
var _api: JavaScriptObject
var _callback: JavaScriptObject
var _busy: bool = false

func open() -> Dictionary:
	if not OS.has_feature("web"): return _failure("web_backend_required")
	var source: String = FileAccess.get_file_as_string("res://services/telemetry/web_telemetry_storage.js")
	if source.is_empty(): return _failure("web_telemetry_backend_missing")
	JavaScriptBridge.eval(source, true)
	var entry: JavaScriptObject = JavaScriptBridge.get_interface("SkillLinesWebTelemetry")
	if entry == null: return _failure("web_telemetry_backend_missing")
	_api = entry.create()
	return await _request("open", "")

func append(name: String, revision: int, text: String) -> Dictionary:
	if _api == null: return _failure("web_telemetry_not_open")
	return await _request("append", JSON.stringify({"name": name, "revision": revision, "text": text}))

func snapshot() -> Dictionary:
	if _api == null: return _failure("web_telemetry_not_open")
	return await _request("snapshot", "")

func _request(method: String, data: String) -> Dictionary:
	if _busy: return _failure("web_telemetry_busy")
	_busy = true
	_callback = JavaScriptBridge.create_callback(_receive)
	if method == "open": _api.open(_callback)
	elif method == "snapshot": _api.snapshot(_callback)
	else: _api.append(data, _callback)
	var result: Dictionary = await completed
	_callback = null
	_busy = false
	return result

func _receive(arguments: Array) -> void:
	if arguments.size() != 1 or not arguments[0] is String:
		completed.emit(_failure("web_telemetry_response_invalid"))
		return
	var value: Variant = JSON.parse_string(arguments[0])
	if not value is Dictionary or value.size() != 3 or not value.get("ok") is bool or not value.get("reason") is String or not value.get("data") is String:
		completed.emit(_failure("web_telemetry_response_invalid"))
		return
	completed.emit(value)

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "data": ""}
