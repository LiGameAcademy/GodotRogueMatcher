extends LocalJsonlSink

## Leaves a real truncated telemetry tail for process-death recovery verification.
func inject_unknown_tail() -> bool:
	if not flush().succeeded() or _file == null: return false
	_file.store_string("{\"unknown_tail\":")
	_file.flush()
	if _file.get_error() != OK: return false
	_closed = true
	return true
