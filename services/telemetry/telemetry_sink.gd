class_name TelemetrySink
extends RefCounted

func append_event(_event: Dictionary) -> TelemetryWriteResult:
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, "sink_not_implemented")

func flush() -> TelemetryWriteResult:
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, "sink_not_implemented")

func close() -> TelemetryWriteResult:
	return flush()
