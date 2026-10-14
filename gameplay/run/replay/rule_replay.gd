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
	return _replay(records, false)

## 从完整命令前缀重建全部状态和随机流；未结束记录仍不能冒充完整回放。
func restore_prefix(records: Array[Dictionary]) -> bool:
	return _replay(records, true)

func _replay(records: Array[Dictionary], prefix: bool) -> bool:
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
	if header.get("rules_version") != RunSnapshot.RULES_VERSION or header.get("offer_version") != SkillOfferGenerator.version_for_mode(StringName(str(config.get("mode_id", "classic_endless")))) or header.get("content_version") != RunSnapshot.digest(config.get("skills")):
		return _fail("record_version_mismatch")
	for key: String in ["columns", "rows", "match_count"]:
		if not CommandCodec.valid_integer(config.get(key)): return _fail("invalid_board_config")
	var columns: int = config.columns.to_int()
	var rows: int = config.rows.to_int()
	var match_count: int = config.match_count.to_int()
	if columns <= 0 or columns > 64 or rows <= 0 or rows > 64 or match_count < 2 or match_count > 128: return _fail("invalid_board_dimensions")
	var stage_config: StageConfig = null
	if not config.get("challenge") is Dictionary: return _fail("invalid_stage_config")
	if not config.challenge.is_empty():
		stage_config = StageConfig.from_record(config.challenge)
		if stage_config == null: return _fail("invalid_stage_config")
	run = RunController.new(BoardRules.new(BoardState.new(columns, rows), match_count), header.seed.to_int(), stage_config)
	run.state.run_id = header.run_id
	if RunSnapshot.digest(RunSnapshot.config(run)) != header.get("config_hash") or RunSnapshot.digest(config) != header.get("config_hash"):
		return _fail("configuration_mismatch")
	if header.get("initialization") not in ["normal", "fixture_f6", "fixture_demolition", "fixture_dye", "fixture_line", "fixture_line_span"]: return _fail("unsupported_initialization")
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
					if expected.status == "completed" and (not run.state.is_game_over or not run.state.rule_error.is_empty() or expected.get("reason") != String(run.state.end_reason) or run.state.end_reason not in [&"board_full", &"challenge_completed"]):
						return _fail("invalid_completed_footer")
					if expected.status == "completed" and run.state.end_reason == &"board_full" and not run.state.rules.state.get_empty_coordinates().is_empty():
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
	if prefix:
		if complete or records.back().get("kind") != "Checkpoint" or generated.records.size() != records.size(): return _fail("unsafe_prefix_boundary")
		if run.state.is_game_over or run.state.phase not in [RunState.Phase.INPUT, RunState.Phase.REWARDS]: return _fail("unsafe_prefix_phase")
		# Header元数据不参与规则比较，但后续工具记录必须保留来源。
		generated.records[0] = header.duplicate(true)
		generated.metadata = header.get("metadata", {}).duplicate(true)
		return true
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

## Human-readable Chinese summary for tools / ResultViewer; keeps machine `error` code intact.
static func describe_error(code: String) -> String:
	if code.is_empty(): return ""
	if code.begins_with("seq=") and code.contains(" expected="):
		return "第%s条记录状态不一致：%s" % [code.get_slice(" ", 0).trim_prefix("seq="), code]
	match code:
		"cannot_read_record": return "无法读取记录文件"
		"incomplete_last_line": return "记录截断：最后一行不完整"
		"invalid_json_line_1", "invalid_record_sequence": return "记录格式或序号无效"
		"missing_header": return "缺少 Header"
		"unsupported_schema": return "不支持的记录 schema"
		"godot_version_mismatch": return "Godot 版本与录制时不一致"
		"invalid_header": return "Header 字段无效"
		"record_version_mismatch": return "规则/内容/候选版本与当前构建不匹配（旧局不能跨版本精确回放）"
		"configuration_mismatch": return "配置指纹与当前规则不一致"
		"initial_state_mismatch": return "初始盘面与记录不一致"
		"incomplete_record_no_footer": return "记录截断：缺少 Footer"
		"record_write_incomplete": return "记录写入不完整（Footer.record_complete=false）"
		"records_after_footer": return "Footer 之后仍有多余记录"
		"unsupported_initialization": return "不支持的初始化方式"
		"invalid_completed_footer", "invalid_rule_error_footer", "invalid_rule_error_reason", "invalid_unfinished_footer":
			return "Footer 终局语义与规则状态不符"
		_: pass
	if code.begins_with("invalid_json_line_"): return "第%s行 JSON 无效" % code.trim_prefix("invalid_json_line_")
	if code.begins_with("seq="): return "回放在序号 %s 失败：%s" % [code.get_slice(" ", 0).trim_prefix("seq="), code]
	return code
