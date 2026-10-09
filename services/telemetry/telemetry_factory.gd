class_name TelemetryFactory
extends RefCounted

const CONFIG: TelemetryConfig = preload("res://services/telemetry/telemetry_config.tres")

var session_id: String
var directory: String = CONFIG.local_directory
var sink_factory: Callable

func _init(session: String = "") -> void:
	session_id = session if not session.is_empty() else "s-" + (str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())).sha256_text().left(24)

func attach(recorder: RunRecorder, run_id: String) -> TelemetryProjector:
	var sink: TelemetrySink = sink_factory.call(run_id) if sink_factory.is_valid() else LocalJsonlSink.new(run_id, directory)
	var projector: TelemetryProjector = TelemetryProjector.new(sink, session_id)
	projector.tool_roles = CONFIG.tool_roles.duplicate()
	recorder.record_appended.connect(projector.observe_record)
	return projector
