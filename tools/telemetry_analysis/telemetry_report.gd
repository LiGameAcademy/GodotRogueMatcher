class_name TelemetryReport
extends RefCounted

var events: Array[Dictionary] = []
var runs: Array[Dictionary] = []
var errors: Array[Dictionary] = []
var _seen: Dictionary[String, String] = {}
var _run_indices: Dictionary[String, int] = {}
var error: String = ""
var _lineage_raw: Array[Dictionary] = []
var _lineage_errors: Array[Dictionary] = []
var _lineage_branches: Array[Dictionary] = []
var _lineage_active: bool = false
var _lineage_dirty: bool = false

func add(values: Array[Dictionary], read_error: String = "") -> void:
	if values.is_empty():
		if not read_error.is_empty(): errors.append({"run_id": null, "reason": read_error})
		return
	var header: Dictionary = values.front()
	if _lineage_active or header.schema_version == TelemetrySchema.RESUME_VERSION:
		if not _lineage_active:
			_lineage_raw.assign(events)
			_lineage_errors.assign(errors)
			_lineage_active = true
		_lineage_raw.append_array(values.duplicate(true))
		if not read_error.is_empty(): _lineage_errors.append({"run_id": header.run_id, "reason": read_error})
		_lineage_dirty = true
		return
	if _run_indices.has(header.run_id) and _dimensions(runs[_run_indices[header.run_id]]) != _dimensions(header):
		errors.append({"run_id": header.run_id, "reason": "conflicting_run_metadata"})
		return
	for event: Dictionary in values:
		var encoded: String = JSON.stringify(event, '', true)
		if _seen.has(event.event_id):
			if _seen[event.event_id] != encoded: errors.append({"run_id": event.run_id, "reason": "conflicting_event_id"})
			continue
		_seen[event.event_id] = encoded
		events.append(event.duplicate(true))
	var row: Dictionary = _base(header)
	var final: Dictionary = values.back()
	if final.event_name == "run_ended": row.merge(final.payload, true)
	else: row.merge({"status": "incomplete", "reason": "missing_ending", "score": "", "moves": "", "choices": "", "record_complete": false})
	if not read_error.is_empty():
		row.status = "incomplete"
		row.reason = read_error
		row.record_complete = false
		errors.append({"run_id": header.run_id, "reason": read_error})
	if _run_indices.has(header.run_id):
		var index: int = _run_indices[header.run_id]
		# 完整记录可补全旧前缀；重复导入旧前缀不能降级已完整的局。
		if row.record_complete or not runs[index].record_complete: runs[index] = row
	else:
		_run_indices[header.run_id] = runs.size()
		runs.append(row)

func summary() -> Dictionary:
	_refresh_lineage()
	var groups: Dictionary = {}
	for run: Dictionary in runs:
		var key: String = _group_key(run) + "/" + run.status
		if not groups.has(key): groups[key] = []
		groups[key].append(run)
	var result: Dictionary = {"schema": "telemetry-report-v1", "runs": runs.size(), "events": events.size(), "errors": errors, "groups": {}, "opportunities": _opportunities()}
	if _lineage_active: result["resume_branches"] = _lineage_branches.duplicate(true)
	for key: String in groups:
		var scores: Array[int] = []
		var moves: Array[int] = []
		for run: Dictionary in groups[key]:
			if TelemetrySchema.valid_integer(run.score): scores.append(run.score.to_int())
			if TelemetrySchema.valid_integer(run.moves): moves.append(run.moves.to_int())
		result.groups[key] = {"dimensions": _dimensions(groups[key][0]), "status": groups[key][0].status, "count": groups[key].size(), "score_p10_p50_p90": _quantiles(scores), "moves_p10_p50_p90": _quantiles(moves)}
	return result

func write(directory: String) -> bool:
	_refresh_lineage()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "cannot_create_report_directory"
		return false
	if not _csv(directory.path_join("runs.csv"), runs): return false
	if _lineage_active:
		var lineage_file: FileAccess = FileAccess.open(directory.path_join("resume_lineage.json"), FileAccess.WRITE)
		if lineage_file == null:
			error = "cannot_write_resume_lineage"
			return false
		lineage_file.store_string(JSON.stringify({"schema": "telemetry-lineage-analysis-v1", "raw_events": _lineage_raw, "branches": _lineage_branches}, "", true, true))
		lineage_file.close()
	var tables: Dictionary[String, Array] = {"turns": [], "offers": [], "inputs": [], "intervals": [], "skills": [], "events": []}
	for event: Dictionary in events:
		var row: Dictionary = _base(event)
		row.merge({"event_id": event.event_id, "telemetry_seq": event.telemetry_seq, "event_name": event.event_name, "elapsed_ms": event.elapsed_ms, "action_id": event.action_id, "turn_index": event.turn_index, "command_id": event.command_id})
		row.merge(event.payload)
		# 保留完整信封，使七表CSV可无损重新导入；扁平列继续供现有分析使用。
		row["event_json"] = event.duplicate(true)
		tables.events.append(row)
		match event.event_name:
			"action_resolved": tables.turns.append(row)
			"turn_resolved":
				if event.schema_version == "1": tables.turns.append(row)
			"offer_generated", "offer_presented": tables.offers.append(row)
			"input_resolved": tables.inputs.append(row)
			"observation_interval_closed": tables.intervals.append(row)
			"skill_acquired": tables.skills.append(row)
	for table: String in tables:
		var rows: Array[Dictionary] = []
		rows.assign(tables[table])
		if not _csv(directory.path_join(table + ".csv"), rows): return false
	var file: FileAccess = FileAccess.open(directory.path_join("summary.json"), FileAccess.WRITE)
	if file == null:
		error = "cannot_write_summary"
		return false
	file.store_string(JSON.stringify(summary(), "\t", true))
	file.flush()
	return file.get_error() == OK

func _refresh_lineage() -> void:
	if not _lineage_dirty: return
	var normalized: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(_lineage_raw)
	events = []
	runs = []
	errors = []
	_seen.clear()
	_run_indices.clear()
	_lineage_branches.assign(normalized.branches)
	_lineage_active = false
	for stream: Array in normalized.streams:
		var typed: Array[Dictionary] = []
		typed.assign(stream)
		add(typed)
	_lineage_active = true
	errors.append_array(normalized.errors)
	var resumed: Dictionary[String, bool] = {}
	for raw: Dictionary in _lineage_raw:
		if raw.schema_version == TelemetrySchema.RESUME_VERSION: resumed[raw.run_id] = true
	for previous: Dictionary in _lineage_errors:
		if previous.reason != "incomplete_telemetry_no_complete_ending" or not resumed.has(str(previous.get("run_id"))): errors.append(previous)
	_lineage_dirty = false

func _opportunities() -> Dictionary:
	return preload("res://tools/telemetry_analysis/offer_measurements.gd").summarize(events, _group_key, _dimensions)

func _base(event: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["run_id", "session_id", "source", "initialization", "schema_version", "rule_version", "content_version", "offer_version", "build_id", "config_hash", "strategy_version", "bot_config_hash", "experiment_id", "variant_id"]: result[key] = event.get(key)
	for key: String in ["mode_id", "collection_context", "commit_id", "pressure_version", "collection_config_hash"]: result[key] = event.get(key, "unknown")
	return result

func _dimensions(event: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["source", "initialization", "schema_version", "rule_version", "content_version", "offer_version", "build_id", "config_hash", "strategy_version", "bot_config_hash", "experiment_id", "variant_id"]: result[key] = event.get(key)
	for key: String in ["mode_id", "collection_context", "commit_id", "pressure_version", "collection_config_hash"]: result[key] = event.get(key, "unknown")
	return result

func _group_key(event: Dictionary) -> String:
	return String(event.source) + "/" + JSON.stringify(_dimensions(event), '', true).sha256_text()

func _quantiles(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	values.sort()
	if values.is_empty(): return result
	for q: float in [0.1, 0.5, 0.9]: result.append(values[int(floor(q * (values.size() - 1)))])
	return result

func _csv(path: String, rows: Array[Dictionary]) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = "cannot_write_csv"
		return false
	var keys: PackedStringArray = ["run_id"]
	for row: Dictionary in rows:
		for key: String in row:
			if not keys.has(key): keys.append(key)
	file.store_csv_line(keys)
	for row: Dictionary in rows:
		var fields: PackedStringArray = []
		for key: String in keys:
			var value: Variant = row.get(key)
			fields.append("" if value == null else JSON.stringify(value, '', true) if value is Dictionary or value is Array else str(value))
		file.store_csv_line(fields)
	file.flush()
	return file.get_error() == OK
