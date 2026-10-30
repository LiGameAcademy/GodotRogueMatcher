extends RefCounted

## Exports one bounded run at a time; global state retains summaries and compact reward facts.
const OBSERVATION: Script = preload("res://tools/telemetry_analysis/bounded_observation.gd")

var maximum_run_bytes: int = 16 * 1024 * 1024
var maximum_line_bytes: int = 1024 * 1024
var maximum_retained_bytes: int = 32 * 1024 * 1024
var maximum_observation_events: int = 20000
var maximum_elapsed_ms: int = 60000
var maximum_files: int = 4096
var error: String = ""
var result: Dictionary = {}
var manifest: Array[Dictionary] = []
var _aggregate: TelemetryReport
var _started: int
var _observation_bytes: int
var _event_count: int
var _peak_run_bytes: int
var _retained_summary_bytes: int
var _omitted_diagnostics: int
var _shards: Array[Dictionary]

func analyze(paths: Array[String], directory: String) -> bool:
	error = ""
	result = {}
	manifest.clear()
	_shards = []
	_observation_bytes = 0
	_event_count = 0
	_peak_run_bytes = 0
	_retained_summary_bytes = 0
	_omitted_diagnostics = 0
	_started = Time.get_ticks_msec()
	_aggregate = TelemetryReport.new()
	_retained_summary_bytes = _metadata_bytes()
	if mini(_minimum_limit(), maximum_files) <= 0: return _fail("invalid_analysis_limits")
	if paths.is_empty(): return _fail("no_telemetry_files")
	if paths.size() > maximum_files: return _fail("analysis_file_limit_exceeded")
	if FileAccess.file_exists(directory): return _fail("analysis_output_is_file")
	var existing: DirAccess = DirAccess.open(directory)
	if existing != null and (not existing.get_files().is_empty() or not existing.get_directories().is_empty()):
		return _fail("analysis_output_not_empty")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _fail("cannot_create_report_directory")
	var groups: Dictionary[String, Array] = _inputs(paths)
	var ids: Array = groups.keys()
	ids.sort()
	for id: String in ids:
		if _expired():
			_issue(id, "analysis_time_budget_exceeded")
			break
		_process_run(id, groups[id], directory)
	if _expired(): _issue(null, "analysis_time_budget_exceeded")
	_retained_summary_bytes = _metadata_bytes()
	if _retained_summary_bytes + _observation_bytes > maximum_retained_bytes: _issue(null, "summary_budget_exceeded")
	result = _aggregate.summary()
	result.events = _event_count
	result["bounded"] = {"protocol": "per-run-shards-v1", "complete": _aggregate.errors.is_empty(),
		"input_files": paths.size(), "processed_runs": _shards.size(), "shards": _shards,
		"inspected_files": manifest.size(), "uninspected_files": paths.size() - manifest.size(),
		"maximum_run_bytes": maximum_run_bytes, "maximum_line_bytes": maximum_line_bytes, "maximum_retained_bytes": maximum_retained_bytes, "retained_budget_protocol": "compact-records-v1",
		"maximum_observation_events": maximum_observation_events, "maximum_elapsed_ms": maximum_elapsed_ms, "maximum_files": maximum_files,
		"peak_run_input_bytes": _peak_run_bytes, "retained_observation_bytes": _observation_bytes,
		"retained_summary_bytes": _retained_summary_bytes, "retained_observation_events": _aggregate.events.size(), "elapsed_ms": Time.get_ticks_msec() - _started}
	result.bounded["omitted_diagnostics"] = _omitted_diagnostics
	if not _json(directory.path_join("manifest.json"), {"protocol": "per-run-shards-v1", "inputs": manifest, "shards": _shards}): return false
	if not _json(directory.path_join("summary.json"), result): return false
	if not _aggregate.errors.is_empty(): error = "bounded_analysis_incomplete"
	return error.is_empty()

func _minimum_limit() -> int:
	return mini(maximum_line_bytes, mini(mini(maximum_run_bytes, maximum_retained_bytes), mini(maximum_elapsed_ms, maximum_observation_events)))

func _inputs(paths: Array[String]) -> Dictionary[String, Array]:
	var groups: Dictionary[String, Array] = {}
	var ordered: Array[String] = paths.duplicate()
	ordered.sort()
	for path: String in ordered:
		if _expired():
			_issue(null, "analysis_time_budget_exceeded")
			break
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			_issue(null, "cannot_read_telemetry", path)
			continue
		var row: Dictionary = {"path": path, "bytes": file.get_length(), "run_id": null, "sha256": null, "status": "pending"}
		var initial_bytes: int = _bytes(row)
		var append_bytes: int = initial_bytes + (1 if not manifest.is_empty() else 0)
		if _retained_summary_bytes + append_bytes > maximum_retained_bytes:
			_issue(null, "summary_budget_exceeded", path)
			break
		_retained_summary_bytes += append_bytes
		manifest.append(row)
		if file.get_length() > maximum_run_bytes:
			row.status = "budget_rejected"
			_issue(null, "run_input_budget_exceeded", path)
			continue
		var line_error: String = _line_budget(file)
		if not line_error.is_empty():
			row.status = "rejected"
			_issue(null, line_error, path)
			continue
		file.seek(0)
		var parser: JSON = JSON.new()
		var parsed: int = parser.parse(file.get_line())
		var header: Variant = parser.data
		file.close()
		if parsed != OK or not header is Dictionary or not TelemetrySchema.validate(header).is_empty() or header.event_name != "run_started":
			row.status = "rejected"
			_issue(null, "invalid_telemetry_header", path)
			continue
		row.run_id = header.run_id
		row.sha256 = FileAccess.get_sha256(path)
		_retained_summary_bytes += _bytes(row) - initial_bytes
		if not groups.has(header.run_id): groups[header.run_id] = []
		groups[header.run_id].append(row)
	return groups

func _process_run(id: String, inputs: Array, directory: String) -> void:
	var bytes: int = 0
	for input: Dictionary in inputs: bytes += input.bytes
	if bytes > maximum_run_bytes:
		for input: Dictionary in inputs: input.status = "budget_rejected"
		_issue(id, "run_input_budget_exceeded")
		return
	_peak_run_bytes = maxi(_peak_run_bytes, bytes)
	var report: TelemetryReport = TelemetryReport.new()
	for input: Dictionary in inputs:
		if _expired():
			_issue(id, "analysis_time_budget_exceeded")
			return
		# Recheck the snapshot before reading; the existing Reader validates every event.
		var file: FileAccess = FileAccess.open(input.path, FileAccess.READ)
		if file == null or file.get_length() != input.bytes or FileAccess.get_sha256(input.path) != input.sha256:
			_issue(id, "analysis_input_changed", input.path)
			return
		file.close()
		var reader: TelemetryReader = TelemetryReader.new()
		report.add(reader.read_file(input.path), reader.error)
		if FileAccess.get_sha256(input.path) != input.sha256:
			_issue(id, "analysis_input_changed", input.path)
			return
	var observations: Array[Dictionary] = []
	var observation_bytes: int = 0
	for event: Dictionary in report.events:
		var compact: Dictionary = OBSERVATION.compact(event)
		if compact.is_empty(): continue
		observations.append(compact)
		observation_bytes += JSON.stringify(compact).to_utf8_buffer().size()
	var shard: String = "runs/" + id.sha256_text()
	var shard_row: Dictionary = {"run_id": id, "path": shard, "events": report.events.size(), "input_bytes": bytes}
	var status: String = "processed" if report.errors.is_empty() else "processed_with_errors"
	var summary_bytes: int = _append_bytes(_aggregate.runs.size(), report.runs) + _append_bytes(_aggregate.errors.size(), report.errors) + _append_bytes(_shards.size(), [shard_row])
	for input: Dictionary in inputs:
		var final_input: Dictionary = input.duplicate(false)
		final_input.status = status
		summary_bytes += _bytes(final_input) - _bytes(input)
	if _retained_summary_bytes + summary_bytes + _observation_bytes + observation_bytes > maximum_retained_bytes or _aggregate.events.size() + observations.size() > maximum_observation_events:
		for input: Dictionary in inputs: input.status = "budget_rejected"
		_issue(id, "observation_budget_exceeded")
		return
	# IDs are case-sensitive; lowercase digests keep Windows paths distinct and avoid device names.
	if not report.write(directory.path_join(shard)):
		for input: Dictionary in inputs: input.status = "export_failed"
		_issue(id, report.error, directory.path_join(shard))
		return
	_observation_bytes += observation_bytes
	_retained_summary_bytes += summary_bytes
	_event_count += report.events.size()
	_aggregate.runs.append_array(report.runs)
	_aggregate.errors.append_array(report.errors)
	_aggregate.events.append_array(observations)
	_shards.append(shard_row)
	for input: Dictionary in inputs: input.status = status
	print("BOUNDED_RUN=%s EVENTS=%d ERRORS=%d" % [id, report.events.size(), report.errors.size()])

func _expired() -> bool:
	return Time.get_ticks_msec() - _started >= maximum_elapsed_ms

func _bytes(value: Variant) -> int:
	return JSON.stringify(value).to_utf8_buffer().size()

func _append_bytes(count: int, additions: Array) -> int:
	var bytes: int = maxi(0, count + additions.size() - 1) - maxi(0, count - 1)
	for value: Variant in additions: bytes += _bytes(value)
	return bytes

func _metadata_bytes() -> int:
	return _bytes({"inputs": manifest, "shards": _shards, "runs": _aggregate.runs, "errors": _aggregate.errors})

func _issue(id: Variant, reason: String, path: String = "") -> void:
	# Limit additional budget/input diagnostics; lossless per-run errors stay in their shards.
	if _aggregate.errors.size() < 256: _aggregate.errors.append({"run_id": id, "reason": reason, "path": path})
	else: _omitted_diagnostics += 1

func _line_budget(file: FileAccess) -> String:
	var line_bytes: int = 0
	while file.get_position() < file.get_length():
		if _expired(): return "analysis_time_budget_exceeded"
		var chunk: PackedByteArray = file.get_buffer(mini(65536, file.get_length() - file.get_position()))
		for byte: int in chunk:
			line_bytes = 0 if byte == 10 else line_bytes + 1
			if line_bytes > maximum_line_bytes: return "telemetry_line_budget_exceeded"
	return ""

func _json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _fail("cannot_write_analysis_manifest")
	file.store_string(JSON.stringify(value, "\t", true))
	file.flush()
	return true if file.get_error() == OK else _fail("cannot_write_analysis_manifest")

func _fail(reason: String) -> bool:
	error = reason
	return false
