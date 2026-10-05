class_name TelemetryReader
extends RefCounted

var error: String = ""
var complete: bool = false

func read_file(path: String) -> Array[Dictionary]:
	error = ""
	complete = false
	var result: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "cannot_read_telemetry"
		return result
	var seen: Dictionary[String, String] = {}
	var last_seq: int = 0
	var run_id: String = ""
	var ended_seen: bool = false
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty() and file.eof_reached(): break
		if file.eof_reached():
			error = "incomplete_last_line"
			break
		var json: JSON = JSON.new()
		if json.parse(line) != OK or not json.data is Dictionary:
			error = "invalid_telemetry_json"
			break
		var event: Dictionary = json.data
		var validation: String = TelemetrySchema.validate(event)
		if not validation.is_empty():
			error = validation
			break
		if seen.has(event.event_id):
			if seen[event.event_id] == RunSnapshot.canonical(event): continue
			error = "conflicting_event_id"
			break
		if event.telemetry_seq.to_int() != last_seq + 1 or (not run_id.is_empty() and event.run_id != run_id):
			error = "telemetry_sequence_gap_or_mixed_run"
			break
		if ended_seen:
			error = "events_after_ending"
			break
		if last_seq == 0 and event.event_name != "run_started":
			error = "missing_run_started"
			break
		run_id = event.run_id
		last_seq += 1
		seen[event.event_id] = RunSnapshot.canonical(event)
		result.append(event)
		if event.event_name == "run_ended":
			ended_seen = true
			complete = event.payload.record_complete
	if error.is_empty() and not complete: error = "incomplete_telemetry_no_complete_ending"
	if not error.is_empty(): complete = false
	return result
