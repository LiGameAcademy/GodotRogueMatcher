class_name TelemetryReport
extends RefCounted

var events: Array[Dictionary] = []
var runs: Array[Dictionary] = []
var errors: Array[Dictionary] = []
var _seen: Dictionary[String, String] = {}
var _run_indices: Dictionary[String, int] = {}
var error: String = ""

func add(values: Array[Dictionary], read_error: String = "") -> void:
	if values.is_empty():
		if not read_error.is_empty(): errors.append({"run_id": null, "reason": read_error})
		return
	var header: Dictionary = values.front()
	if _run_indices.has(header.run_id) and _dimensions(runs[_run_indices[header.run_id]]) != _dimensions(header):
		errors.append({"run_id": header.run_id, "reason": "conflicting_run_metadata"})
		return
	for event: Dictionary in values:
		var encoded: String = RunSnapshot.canonical(event)
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
	var groups: Dictionary = {}
	for run: Dictionary in runs:
		var key: String = _group_key(run) + "/" + run.status
		if not groups.has(key): groups[key] = []
		groups[key].append(run)
	var result: Dictionary = {"schema": "telemetry-report-v1", "runs": runs.size(), "events": events.size(), "errors": errors, "groups": {}, "opportunities": _opportunities()}
	for key: String in groups:
		var scores: Array[int] = []
		var moves: Array[int] = []
		for run: Dictionary in groups[key]:
			if CommandCodec.valid_integer(run.score): scores.append(run.score.to_int())
			if CommandCodec.valid_integer(run.moves): moves.append(run.moves.to_int())
		result.groups[key] = {"dimensions": _dimensions(groups[key][0]), "status": groups[key][0].status, "count": groups[key].size(), "score_p10_p50_p90": _quantiles(scores), "moves_p10_p50_p90": _quantiles(moves)}
	return result

func write(directory: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "cannot_create_report_directory"
		return false
	if not _csv(directory.path_join("runs.csv"), runs): return false
	var tables: Dictionary[String, Array] = {"turns": [], "offers": [], "inputs": [], "intervals": [], "skills": [], "events": []}
	for event: Dictionary in events:
		var row: Dictionary = _base(event)
		row.merge({"event_id": event.event_id, "telemetry_seq": event.telemetry_seq, "event_name": event.event_name, "elapsed_ms": event.elapsed_ms, "action_id": event.action_id, "turn_index": event.turn_index, "command_id": event.command_id})
		row.merge(event.payload)
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

func _opportunities() -> Dictionary:
	var generated: Dictionary[String, Dictionary] = {}
	var presented: Dictionary[String, bool] = {}
	var acquired: Dictionary[String, String] = {}
	var failed_choices: int = 0
	for event: Dictionary in events:
		var data: Dictionary = event.payload
		var key: String = event.run_id + ":" + String(data.get("offer_id", ""))
		match event.event_name:
			"offer_generated": generated[key] = event
			"offer_presented": presented[key] = true
			"skill_acquired": acquired[key] = data.skill_id
			"command_resolved":
				if data.type == "choose" and not data.accepted: failed_choices += 1
	var skills: Dictionary = {}
	var unseen: int = 0
	var unconsumed: int = 0
	for key: String in generated:
		var event: Dictionary = generated[key]
		var opportunity: bool = event.source == "bot" or (event.source in ["human", "fixture"] and presented.has(key))
		if event.source == "human" and not presented.has(key): unseen += 1
		if presented.has(key) and not acquired.has(key): unconsumed += 1
		for id: String in event.payload.choices:
			var group: String = _group_key(event) + "/" + id
			if not skills.has(group): skills[group] = {"dimensions": _dimensions(event), "skill_id": id, "generated": 0, "opportunities": 0, "acquired": 0}
			skills[group].generated += 1
			if opportunity:
				skills[group].opportunities += 1
				if acquired.get(key) == id: skills[group].acquired += 1
	for key: String in skills:
		var row: Dictionary = skills[key]
		row["conditional_selection_rate"] = float(row.acquired) / row.opportunities if row.opportunities > 0 else null
	return {"skills": skills, "human_generated_not_presented": unseen, "presented_not_consumed": unconsumed, "failed_choices": failed_choices, "eligibility_rate": null}

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
	return String(event.source) + "/" + RunSnapshot.digest(_dimensions(event))

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
			fields.append("" if value == null else RunSnapshot.canonical(value) if value is Dictionary or value is Array else str(value))
		file.store_csv_line(fields)
	file.flush()
	return file.get_error() == OK
