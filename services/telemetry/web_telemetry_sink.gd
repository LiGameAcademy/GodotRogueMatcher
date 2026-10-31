extends TelemetrySink

## Observation segment with independent accepted and transaction-confirmed positions.
const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
var path: String = ""
var error: String = ""
var accepted_seq: int = 0
var completion_state: Callable
var persisted_seq: int:
	get: return _backend.persisted_sequence(path)
var _backend: BACKEND
var _closed: bool = false
var _terminal: Dictionary = {}

func _init(storage_id: String, backend: BACKEND) -> void:
	_backend = backend
	path = "telemetry/" + storage_id + ".jsonl"
	if not TelemetrySchema.safe_id(storage_id) or not _backend.reserve(path): error = "web_telemetry_file_unavailable"

func append_event(event: Dictionary) -> TelemetryWriteResult:
	if _closed: return _failed("sink_closed")
	if not error.is_empty(): return _failed(error)
	var validation: String = TelemetrySchema.validate(event)
	if not validation.is_empty(): return _failed(validation)
	if not _terminal.is_empty(): return _failed("web_telemetry_terminal_pending")
	var sequence: int = int(event.telemetry_seq)
	if sequence != accepted_seq + 1: return _failed("web_telemetry_sequence_mismatch")
	if event.event_name in ["run_ended", "resume_segment_closed"] and completion_state.is_valid():
		accepted_seq = sequence
		_terminal = event.duplicate(true)
		_complete_terminal.call_deferred()
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.ACCEPTED)
	if not _backend.append(path, JSON.stringify(event, "", true) + "\n", sequence):
		return _failed(_backend.error if not _backend.error.is_empty() else "web_telemetry_append_rejected")
	accepted_seq = sequence
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.ACCEPTED)

func flush() -> TelemetryWriteResult:
	if not _backend.error.is_empty(): return _failed(_backend.error)
	if not error.is_empty(): return _failed(error)
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED if persisted_seq == accepted_seq else TelemetryWriteResult.Status.ACCEPTED)

func close() -> TelemetryWriteResult:
	_closed = true
	return flush()

func diagnostics() -> Dictionary:
	return {"accepted_seq": accepted_seq, "persisted_seq": persisted_seq, "error": error if not error.is_empty() else _backend.error, "path": path}

func _failed(reason: String) -> TelemetryWriteResult:
	error = reason
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, reason)

## Raw rule evidence must be acknowledged before a natural ending can claim completeness.
func _complete_terminal() -> void:
	var state: Dictionary = completion_state.call()
	while not state.ready and String(state.error).is_empty() and _backend.error.is_empty():
		await (Engine.get_main_loop() as SceneTree).process_frame
		state = completion_state.call()
	if not String(state.error).is_empty() and _terminal.payload.has("record_complete"):
		_terminal.payload.record_complete = false
		_terminal.payload["record_error"] = state.error
	if not _backend.append(path, JSON.stringify(_terminal, "", true) + "\n", accepted_seq):
		_failed(_backend.error if not _backend.error.is_empty() else "web_telemetry_append_rejected")
	_terminal.clear()
