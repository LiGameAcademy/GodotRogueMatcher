class_name LocalJsonlSink
extends TelemetrySink

const JSON_CODEC: Script = preload("res://addons/godot_core_system/source/utils/io_strategies/serialization/json_serialization_strategy.gd")
var path: String = ""
var error: String = ""
var _file: FileAccess
var _closed: bool = false
var _codec: RefCounted = JSON_CODEC.new()

func _init(run_id: String, directory: String = "user://telemetry") -> void:
	_codec.set("indent", "")
	_codec.set("sort_keys", true)
	if not TelemetrySchema.safe_id(run_id):
		error = "invalid_run_id"
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "cannot_create_telemetry_directory"
		return
	path = directory.path_join(run_id + ".jsonl")
	# 新局只创建新文件，不覆盖旧局或截断文件。
	if FileAccess.file_exists(path):
		error = "telemetry_file_already_exists"
		return
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null: error = "cannot_open_telemetry_file"

func append_event(event: Dictionary) -> TelemetryWriteResult:
	if _closed: return _failed("sink_closed")
	var validation: String = TelemetrySchema.validate(event)
	if not validation.is_empty(): return _failed(validation)
	if not error.is_empty(): return _failed(error)
	var bytes: PackedByteArray = _codec.call("serialize", event.duplicate(true))
	if not String(_codec.get("last_error")).is_empty(): return _failed(String(_codec.get("last_error")))
	_file.store_buffer(bytes)
	_file.store_8(10)
	if _file.get_error() != OK: return _failed("telemetry_write_failed")
	return TelemetryWriteResult.new()

func flush() -> TelemetryWriteResult:
	if not error.is_empty(): return _failed(error)
	if _closed or _file == null: return _failed("sink_closed")
	_file.flush()
	if _file.get_error() != OK: return _failed("telemetry_flush_failed")
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)

func close() -> TelemetryWriteResult:
	if _closed: return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED) if error.is_empty() else _failed(error)
	var result: TelemetryWriteResult = flush()
	if _file != null:
		_file.close()
		_file = null
	_closed = true
	return result

func _failed(reason: String) -> TelemetryWriteResult:
	error = reason
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, reason)
