class_name TelemetrySink
extends RefCounted

func append_event(_event: Dictionary) -> TelemetryWriteResult:
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, "sink_not_implemented")

func flush() -> TelemetryWriteResult:
	return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, "sink_not_implemented")

func close() -> TelemetryWriteResult:
	return flush()

## A negative accepted position means an in-memory sink has no persistence watermark.
func diagnostics() -> Dictionary:
	return {"accepted_seq": -1, "persisted_seq": 0, "error": ""}
