class_name RunRecorder
extends RefCounted

signal record_appended(record: Dictionary)

const SCHEMA: String = "run-jsonl-v1"
var records: Array[Dictionary] = []
var path: String = ""
var error: String = ""
var ended: bool = false
var source: String = "human"
var metadata: Dictionary = {}
var _file: FileAccess
var _start_ms: int = Time.get_ticks_msec()
var _interval_start: int = _start_ms
var _interval: String = "busy"
var times: Dictionary[String, int] = {"pause": 0, "choice": 0, "busy": 0, "input": 0, "robot_compute": 0, "buffer_wait": 0}

func begin(run: RunController, execution_source: String, save_file: bool = true, build: String = "unknown", directory: String = "user://run_records") -> void:
	source = execution_source
	if save_file:
		var code: Error = DirAccess.make_dir_recursive_absolute(directory)
		if code == OK:
			path = directory.path_join(run.state.run_id + ".jsonl")
			_file = FileAccess.open(path, FileAccess.WRITE)
		if _file == null: _fail("本局记录不完整：无法创建JSONL文件")
	var config: Dictionary = RunSnapshot.config(run)
	if build == "unknown": build = str(ProjectSettings.get_setting("application/config/version", "development"))
	append("Header", {"schema_version": SCHEMA, "run_id": run.state.run_id, "source": source, "rules_version": RunSnapshot.RULES_VERSION, "content_version": RunSnapshot.digest(config.skills), "offer_version": SkillOfferGenerator.CONFIG.rules_version, "build": build, "godot": Engine.get_version_info().string, "platform": OS.get_name(), "config": config, "config_hash": RunSnapshot.digest(config), "seed": str(run.state.random.seed), "initialization": run.initialization, "initial": RunSnapshot.capture(run), "metadata": metadata, "support": "normal_pool_and_fixture_f6"})
	checkpoint(run)
	_flush()
	set_interval("input")

func set_interval(next: String) -> void:
	var now: int = Time.get_ticks_msec()
	if times.has(_interval): times[_interval] += now - _interval_start
	_interval_start = now
	_interval = next

func append(kind: String, payload: Dictionary) -> void:
	if ended: return
	var record: Dictionary = payload.duplicate(true)
	record["kind"] = kind
	record["seq"] = str(records.size() + 1)
	record["elapsed_ms"] = str(Time.get_ticks_msec() - _start_ms)
	record = RunSnapshot.normalize(record)
	records.append(record)
	record_appended.emit(record.duplicate(true))
	if _file != null and error.is_empty():
		_file.store_line(RunSnapshot.canonical(record))
		if _file.get_error() != OK: _fail("本局记录不完整：JSONL写入或刷新失败")

func command(run: RunController, request: RunCommand, result: CommandResult, before: Dictionary) -> void:
	set_interval("busy")
	times.buffer_wait += request.buffered_wait_ms
	append("CommandAttempt", {"command": CommandCodec.encode(request), "accepted": result.accepted, "reason": result.reason, "rule_error": result.rule_error, "action_before": before.action})
	var events: Array[Dictionary] = []
	if result.turn != null: events = matches(result.turn.matches)
	var movement: Dictionary = {}
	if result.turn != null and result.turn.move != null and result.turn.move.is_valid():
		movement = {"piece_id": str(result.turn.move.piece_id), "path": RunSnapshot.normalize(result.turn.move.path)}
	if result.skill != null:
		events = matches(result.skill.matches)
		if result.accepted:
			append("SkillAcquired", {"command_id": str(request.command_id), "offer_id": str(result.skill.offer_id), "reward_id": str(result.skill.reward_id), "skill_id": String(result.skill.skill_id), "created": pieces(result.skill.created), "removed": pieces(result.skill.removed), "marked_ids": result.skill.marked_ids, "count_before": before.acquired.get(String(result.skill.skill_id), "0"), "count_after": str(run.state.rewards.acquired.get(result.skill.skill_id, 0)), "levels_before": before.levels, "levels_after": RunSnapshot.capture(run).levels})
	append("RuleResult", {"command_id": str(request.command_id), "events": events, "removed": pieces(result.turn.removed) if result.turn != null else [], "move": movement, "before": before, "after": RunSnapshot.capture(run)})
	checkpoint(run)
	_flush()

func step(run: RunController, result: RunStepResult) -> void:
	var births: Array[Dictionary] = []
	for spawn: SpawnResult in result.spawns:
		births.append({"piece": RunSnapshot.piece(spawn.piece), "events": matches(spawn.matches)})
	append("RuleResult", {"stage": String(result.kind), "births": births, "events": matches(result.matches), "after": RunSnapshot.capture(run)})
	checkpoint(run)
	_flush()

func offer(run: RunController, value: SkillOffer, refresh_reason: String = "") -> void:
	append("Offer", {"offer": RunSnapshot.offer_data(value), "refresh_reason": refresh_reason, "random": RunSnapshot.capture(run).random})
	checkpoint(run)
	_flush()

func checkpoint(run: RunController) -> void:
	var state: Dictionary = RunSnapshot.capture(run)
	append("Checkpoint", {"state": state, "hash": RunSnapshot.digest(state)})

func finish(run: RunController, status: String, reason: String) -> void:
	if ended: return
	set_interval(_interval)
	append("Footer", {"status": status, "reason": reason, "score": str(run.state.ledger.total), "moves": str(run.state.valid_moves), "activations": str(run.state.activations), "actions": str(run.state.valid_moves + run.state.activations), "choices": str(run.state.rewards.consumed_count), "times": times, "source": source, "record_complete": error.is_empty(), "last_valid_seq": str(records.size()), "final": RunSnapshot.capture(run)})
	ended = true
	_flush()
	if _file != null:
		_file.close()
		_file = null

func _fail(message: String) -> void:
	error = message
	push_warning(message)

func _flush() -> void:
	if _file != null and error.is_empty():
		_file.flush()
		if _file.get_error() != OK: _fail("本局记录不完整：JSONL刷新失败")

static func pieces(values: Array[PieceState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: PieceState in values: result.append(RunSnapshot.piece(value))
	return result

static func matches(values: Array[MatchResult]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: MatchResult in values:
		result.append(RunSnapshot.normalize({"cause": value.cause, "removed": pieces(value.removed), "recolored": pieces(value.recolored), "previous_colors": value.previous_colors, "source_color": value.source_color, "center": value.center, "source_id": value.source_id, "radius": value.radius, "generation": value.generation, "score": RunSnapshot.score(value.score_entry)}))
	return result
