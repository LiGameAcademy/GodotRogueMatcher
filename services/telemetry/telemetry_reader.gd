class_name TelemetryReader
extends RefCounted

var error: String = ""
var complete: bool = false
var segment_complete: bool = false

func read_file(path: String) -> Array[Dictionary]:
	error = ""
	complete = false
	segment_complete = false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "cannot_read_telemetry"
		return []
	var text: String = file.get_as_text()
	file.close()
	return read_text(text)

## Same validation for an acknowledged browser prefix; no temporary file or data rewriting.
func read_text(text: String) -> Array[Dictionary]:
	error = ""
	complete = false
	segment_complete = false
	var result: Array[Dictionary] = []
	var seen: Dictionary[String, String] = {}
	var last_seq: int = 0
	var run_id: String = ""
	var ended_seen: bool = false
	var segment_id: String = ""
	var lines: PackedStringArray = text.split("\n", true)
	for index: int in range(lines.size()):
		var line: String = lines[index]
		if index == lines.size() - 1:
			if line.is_empty(): break
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
			if seen[event.event_id] == JSON.stringify(event, '', true): continue
			error = "conflicting_event_id"
			break
		if event.telemetry_seq.to_int() != last_seq + 1 or (not run_id.is_empty() and event.run_id != run_id) or (last_seq > 0 and event.get("segment_id", event.session_id) != segment_id):
			error = "telemetry_sequence_gap_or_mixed_run"
			break
		if ended_seen:
			error = "events_after_ending"
			break
		if last_seq == 0 and event.event_name != ("run_resumed" if event.schema_version == TelemetrySchema.RESUME_VERSION else "run_started"):
			error = "missing_run_started"
			break
		run_id = event.run_id
		segment_id = event.get("segment_id", event.session_id)
		last_seq += 1
		seen[event.event_id] = JSON.stringify(event, '', true)
		result.append(event)
		if event.event_name == "run_ended":
			ended_seen = true
			complete = event.payload.record_complete
		elif event.event_name == "resume_segment_closed":
			ended_seen = true
			segment_complete = true
	if error.is_empty() and not complete and not segment_complete: error = "incomplete_telemetry_no_complete_ending"
	if not error.is_empty(): complete = false
	return result
