class_name LocalJsonlSink
extends TelemetrySink

var path: String = ""
var error: String = ""
var created: bool = false
var _file: FileAccess
var _closed: bool = false
var accepted_seq: int = 0
var persisted_seq: int = 0
var flush_count: int = 0
var serialize_usec: int = 0
var write_usec: int = 0
var peak_bytes: int = 0
var maximum_bytes: int = 4194304
var _pending: PackedByteArray = PackedByteArray()

func _init(run_id: String, directory: String = "user://telemetry") -> void:
	if not TelemetrySchema.safe_id(run_id):
		error = "invalid_run_id"
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "cannot_create_telemetry_directory"
		return
	path = directory.path_join(run_id + ".jsonl")
	if FileAccess.file_exists(path):
		error = "telemetry_file_already_exists"
		return
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null: error = "cannot_open_telemetry_file"
	else: created = true

func append_event(event: Dictionary) -> TelemetryWriteResult:
	var validation: String = TelemetrySchema.validate(event)
	if not validation.is_empty(): return _failed(validation)
	return append_validated(event)

## Projector已经校验；外部文件/工具仍从append_event进入。
func append_validated(event: Dictionary) -> TelemetryWriteResult:
	if _closed: return _failed("sink_closed")
	if not error.is_empty(): return _failed(error)
	var started: int = Time.get_ticks_usec()
	var bytes: PackedByteArray = (JSON.stringify(event, "", true) + "\n").to_utf8_buffer()
	serialize_usec += Time.get_ticks_usec() - started
	if _pending.size() + bytes.size() > maximum_bytes: return _failed("telemetry_queue_limit")
	_pending.append_array(bytes)
	accepted_seq = int(event.telemetry_seq)
	peak_bytes = maxi(peak_bytes, _pending.size())
	return TelemetryWriteResult.new()

func flush() -> TelemetryWriteResult:
	if not error.is_empty(): return _failed(error)
	if _closed or _file == null: return _failed("sink_closed")
	if _pending.is_empty(): return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)
	var started: int = Time.get_ticks_usec()
	_file.store_buffer(_pending)
	_file.flush()
	write_usec += Time.get_ticks_usec() - started
	flush_count += 1
	if _file.get_error() != OK: return _failed("telemetry_flush_failed")
	persisted_seq = accepted_seq
	_pending.clear()
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)

func close() -> TelemetryWriteResult:
	if _closed: return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED) if error.is_empty() else _failed(error)
	var result: TelemetryWriteResult = flush()
	if _file != null: _file.close()
	_file = null
	_closed = true
	return result

func _failed(reason: String) -> TelemetryWriteResult:
	error = reason
	_pending.clear()
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, reason)

func diagnostics() -> Dictionary:
	return {"accepted_seq": accepted_seq, "persisted_seq": persisted_seq, "flush_count": flush_count, "serialize_usec": serialize_usec, "write_usec": write_usec, "queue_bytes": _pending.size(), "peak_bytes": peak_bytes, "error": error}
