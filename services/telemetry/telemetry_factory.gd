class_name TelemetryFactory
extends RefCounted
signal attached(recorder: RunRecorder, projector: TelemetryProjector)

const CONFIG: TelemetryConfig = preload("res://services/telemetry/telemetry_config.tres")

var session_id: String
var directory: String = CONFIG.local_directory
var sink_factory: Callable
var recorders: Array[RunRecorder] = []
var projectors: Array[TelemetryProjector] = []
var collection_context: String = "unknown"
var record_directory: String = "user://run_records"
var commit_id: String = "unknown"

func _init(session: String = "") -> void:
	session_id = session if not session.is_empty() else "s-" + (str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())).sha256_text().left(24)

func attach(recorder: RunRecorder, run_id: String) -> TelemetryProjector:
	var sink: TelemetrySink = sink_factory.call(run_id) if sink_factory.is_valid() else LocalJsonlSink.new(run_id, directory)
	var projector: TelemetryProjector = TelemetryProjector.new(sink, session_id)
	projector.tool_roles = CONFIG.tool_roles.duplicate()
	if recorder.metadata.get("collection_context", "unknown") == "unknown": recorder.metadata["collection_context"] = collection_context
	if not recorder.metadata.has("commit_id"): recorder.metadata["commit_id"] = commit_id
	recorder.maximum_bytes = CONFIG.maximum_queue_bytes
	if sink is LocalJsonlSink: (sink as LocalJsonlSink).maximum_bytes = CONFIG.maximum_queue_bytes
	recorder.record_appended.connect(projector.observe_record)
	recorder.recording_finished.connect(projector.write_summary)
	recorders.append(recorder)
	projectors.append(projector)
	attached.emit(recorder, projector)
	return projector
