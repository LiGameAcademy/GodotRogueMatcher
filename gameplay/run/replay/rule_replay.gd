class_name RuleReplay
extends RefCounted

var error: String = ""
var complete: bool = false
var checked_records: int = 0
var run: RunController

func read_file(path: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	error = ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "cannot_read_record"
		return records
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty() and file.eof_reached(): break
		if file.eof_reached():
			error = "incomplete_last_line"
			break
		var json: JSON = JSON.new()
		if json.parse(line) != OK or not json.data is Dictionary:
			error = "invalid_json_line_%d" % (records.size() + 1)
			break
		var value: Dictionary = json.data
		if not CommandCodec.valid_integer(value.get("seq")) or value.seq.to_int() != records.size() + 1:
			error = "invalid_record_sequence"
			break
		records.append(value)
	return records

func replay_file(path: String) -> bool:
	var records: Array[Dictionary] = read_file(path)
	var read_error: String = error
	var result: bool = replay(records)
	if not read_error.is_empty():
		error = read_error
		complete = false
		return false
	return result

func replay(records: Array[Dictionary]) -> bool:
	error = ""
	complete = false
	checked_records = 0
	if records.is_empty() or records[0].get("kind") != "Header": return _fail("missing_header")
	var header: Dictionary = records[0]
	if header.get("schema_version") != RunRecorder.SCHEMA: return _fail("unsupported_schema")
	if header.get("godot") != Engine.get_version_info().string: return _fail("godot_version_mismatch")
	if not CommandCodec.valid_integer(header.get("seed")) or not header.get("config") is Dictionary or not header.get("run_id") is String:
		return _fail("invalid_header")
	var config: Dictionary = header.config
	if header.get("rules_version") != RunSnapshot.RULES_VERSION or header.get("offer_version") != SkillOfferGenerator.CONFIG.rules_version or header.get("content_version") != RunSnapshot.digest(config.get("skills")):
		return _fail("record_version_mismatch")
	for key: String in ["columns", "rows", "match_count"]:
		if not CommandCodec.valid_integer(config.get(key)): return _fail("invalid_board_config")
	var columns: int = config.columns.to_int()
	var rows: int = config.rows.to_int()
	var match_count: int = config.match_count.to_int()
	if columns <= 0 or columns > 64 or rows <= 0 or rows > 64 or match_count < 2 or match_count > 128: return _fail("invalid_board_dimensions")
	run = RunController.new(BoardRules.new(BoardState.new(columns, rows), match_count), header.seed.to_int())
	run.state.run_id = header.run_id
	if RunSnapshot.digest(RunSnapshot.config(run)) != header.get("config_hash") or RunSnapshot.digest(config) != header.get("config_hash"):
		return _fail("configuration_mismatch")
	if header.get("initialization") not in ["normal", "fixture_f6", "fixture_demolition"]: return _fail("unsupported_initialization")
	run.initialize(header.initialization)
	if RunSnapshot.canonical(RunSnapshot.capture(run)) != RunSnapshot.canonical(header.get("initial")): return _fail("initial_state_mismatch")
	var generated: RunRecorder = RunRecorder.new()
	run.recorder = generated
	generated.begin(run, String(header.get("source", "replay")), false)
	for index: int in range(1, records.size()):
		var expected: Dictionary = records[index]
		if not CommandCodec.valid_integer(expected.get("seq")) or expected.seq.to_int() != index + 1:
			return _fail("seq=%d invalid_sequence" % (index + 1))
		if generated.records.size() <= index:
			match expected.get("kind"):
				"CommandAttempt":
					if not expected.get("command") is Dictionary: return _fail("invalid_command_payload")
					var command: RunCommand = CommandCodec.decode(expected.command)
					if command == null: return _fail("seq=%d invalid_command" % (index + 1))
					run.execute_command(command)
				"Offer": run.prepare_offer()
				"Diagnostic":
					if not expected.get("reason") is String or expected.reason.is_empty(): return _fail("invalid_diagnostic")
					run.report_error(expected.reason)
				"RuleResult":
					if expected.has("stage"): run.advance()
					else: return _fail("seq=%d missing_command_result" % (index + 1))
				"Footer":
					if expected.get("status") not in ["completed", "abandoned", "rule_error", "censored"]: return _fail("invalid_footer_status")
					if expected.status == "completed" and (not run.state.is_game_over or not run.state.rule_error.is_empty() or expected.get("reason") != "board_full" or not run.state.rules.state.get_empty_coordinates().is_empty()):
						return _fail("invalid_completed_footer")
					if expected.status == "rule_error" and run.state.rule_error.is_empty(): return _fail("invalid_rule_error_footer")
					if expected.status == "rule_error" and expected.get("reason") != run.state.rule_error: return _fail("invalid_rule_error_reason")
					if expected.status in ["censored", "abandoned"] and run.state.is_game_over: return _fail("invalid_unfinished_footer")
					generated.finish(run, expected.status, String(expected.get("reason", "")))
				_: return _fail("seq=%d unsupported_or_missing_record" % (index + 1))
		if generated.records.size() <= index: return _fail("seq=%d phase_cannot_advance" % (index + 1))
		var actual: Dictionary = generated.records[index]
		var expected_value: Dictionary = _without_time(expected)
		var actual_value: Dictionary = _without_time(actual)
		# v1首批记录没有表现路径；规则状态与事件仍逐项验证。
		if not expected.has("move"): actual_value.erase("move")
		if RunSnapshot.canonical(expected_value) != RunSnapshot.canonical(actual_value):
			return _fail("seq=%d phase=%s %s" % [index + 1, RunState.Phase.keys()[run.state.phase], _difference(expected_value, actual_value, "")])
		checked_records = index + 1
		if expected.get("kind") == "Footer":
			if index != records.size() - 1: return _fail("records_after_footer")
			if not expected.get("record_complete", false): return _fail("record_write_incomplete")
			complete = true
	if not complete: return _fail("incomplete_record_no_footer")
	return true

func _without_time(record: Dictionary) -> Dictionary:
	var result: Dictionary = record.duplicate(true)
	result.erase("elapsed_ms")
	if result.get("kind") == "Footer": result.erase("times")
	return result

func _difference(expected: Variant, actual: Variant, path: String) -> String:
	if expected is Dictionary and actual is Dictionary:
		var keys: Array = expected.keys()
		keys.sort()
		for key: String in keys:
			if not actual.has(key): return path + "." + key + " missing"
			if RunSnapshot.canonical(expected[key]) != RunSnapshot.canonical(actual[key]): return _difference(expected[key], actual[key], path + "." + key)
	return "%s expected=%s actual=%s" % [path, RunSnapshot.canonical(expected).left(160), RunSnapshot.canonical(actual).left(160)]

func _fail(reason: String) -> bool:
	error = reason
	return false
