class_name TelemetryProjector
extends RefCounted

var events: Array[Dictionary] = []
var error: String = ""
var ended: bool = false
var sink: TelemetrySink
var clock: TelemetryClock
var tool_roles: Dictionary[String, String] = {}
var _session_id: String
var _base: Dictionary = {}
var _seq: int = 0
var _state: Dictionary = {}
var _command: Dictionary = {}
var _skill: Dictionary = {}
var _pending_offer: Dictionary = {}
var _offers: Dictionary[String, bool] = {}
var _presentation_seq: int = 0
var _input_seq: int = 0
var _inputs: Dictionary[String, Dictionary] = {}
var _turn: TelemetryTurn
var _config: Dictionary = {}
var _ui: String = "presentation"
var _summary: Dictionary = {}
var _action_type: String = ""
var _complete_actions: int = 0
var _last_complete_action: String = "0"
var _last_input_ms: int = 0
var _last_observation_utc: String = ""
var _last_submitted: Dictionary = {}
var _last_skill: Dictionary = {}
var _root_incomplete: bool = false
var _pressure_cache: Dictionary[String, Dictionary] = {}
var _play_started: bool = false
var summary_path: String = ""
var needs_flush: bool = false

func _init(destination: TelemetrySink, session_id: String, timer: Callable = Callable()) -> void:
	sink = destination
	_session_id = session_id
	clock = TelemetryClock.new(timer)

## 只消费Recorder冻结后的事实，不持有RunController、Node或随机对象。
func observe_record(row: Dictionary) -> void:
	if ended: return
	match row.kind:
		"Header": _start(row)
		"CommandAttempt": _command = row.duplicate(true)
		"SkillAcquired": _skill = row.duplicate(true)
		"Offer": _pending_offer = row.offer.duplicate(true)
		"Checkpoint":
			_state = row.state
			if not _pending_offer.is_empty(): _generated_offer()
		"RuleResult": _resolved(row)
		"Footer": _finish(row)

func set_interval(category: String) -> void:
	if ended or _base.is_empty() or not clock.times.has(category) or category == clock.category: return
	_emit("observation_interval_closed", clock.change(category))

func offer_presented(offer_id: int, order: Array[String]) -> bool:
	if ended or _base.get("source") not in ["human", "fixture"] or not _offers.has(str(offer_id)): return false
	_presentation_seq += 1
	_emit("offer_presented", {"offer_id": str(offer_id), "presentation_id": "%s:p:%d" % [_base.run_id, _presentation_seq], "choices": order.duplicate(), "density": _density()})
	return true

func begin_input(type: String, buffered: bool = false) -> String:
	if ended or _base.is_empty(): return ""
	_input_seq += 1
	_last_input_ms = clock.elapsed()
	var id: String = "%s:i:%d" % [_base.run_id, _input_seq]
	_inputs[id] = {"input_id": id, "type": type, "buffered": buffered}
	return id

func resolve_input(id: String, disposition: String, reason: String, command_id: Variant = null, wait_ms: int = 0) -> void:
	if ended or not _inputs.has(id): return
	var payload: Dictionary = _inputs[id].duplicate(true)
	_inputs.erase(id)
	payload.merge({"disposition": disposition, "reason": reason, "buffer_wait_ms": maxi(0, wait_ms)})
	_emit("input_resolved", payload, {"command_id": command_id})

func _start(header: Dictionary) -> void:
	_state = header.initial.duplicate(true)
	_config = header.config.duplicate(true)
	_base = {"schema_version": TelemetrySchema.VERSION, "run_id": header.run_id, "session_id": _session_id, "rule_version": header.rules_version, "content_version": header.content_version, "offer_version": header.offer_version, "build_id": header.build, "config_hash": header.config_hash, "source": header.source, "initialization": header.initialization, "action_id": null, "turn_index": null, "command_id": null, "experiment_id": header.metadata.get("experiment_id"), "variant_id": header.metadata.get("variant_id"), "strategy_version": header.metadata.get("strategy"), "columns": header.config.columns, "rows": header.config.rows}
	# 初始化规则与文件创建不冒充玩家观察区间。
	var bot_config: Dictionary = header.metadata.get("bot_config", {})
	_base["bot_config_hash"] = null if bot_config.is_empty() else RunSnapshot.digest(bot_config)
	_base.merge({"mode_id": header.config.mode_id, "collection_context": header.metadata.get("collection_context", "bot_batch" if header.source == "bot" else "fixture" if header.source == "fixture" else "unknown"), "commit_id": header.metadata.get("commit_id", "unknown"), "seed": header.seed, "pressure_version": TelemetryFacts.CONFIG.pressure_version, "collection_config_hash": RunSnapshot.digest(RunSnapshot.resource_fields(TelemetryFacts.CONFIG)), "rule_event_id": null, "parent_event_id": null, "root_action_id": null, "batch_id": null, "stage_id": null, "reward_id": null, "offer_id": null})
	if header.source in ["bot", "fixture"]: _base["collection_context"] = "bot_batch" if header.source == "bot" else "fixture"
	clock = TelemetryClock.new(clock.time_source())
	var companions: int = 0
	for piece: Dictionary in _state.pieces:
		if not piece.content_id.is_empty(): companions += 1
	_emit("run_started", {"columns": header.config.columns, "rows": header.config.rows, "ordinary": _state.pieces.size() - companions, "companions": companions, "score": _state.total, "config": _config, "pressure_config": RunSnapshot.resource_fields(TelemetryFacts.CONFIG), "capabilities": {"goal_effects": true, "implemented_goal_effects": ["goal_score_bonus"], "rescue_weights": not _config.get("challenge", {}).is_empty(), "target_curve": false, "all_ability_attempts": false}, "initial_observation": observation()})

func _resolved(row: Dictionary) -> void:
	_state = row.after
	if row.has("command_id") and not _command.is_empty():
		var request: Dictionary = _command.command
		var context: Dictionary = {"command_id": request.command_id}
		if _command.accepted and request.type in ["move", "detonate"]:
			_turn = TelemetryTurn.new(row.before, request.command_id, row.after.action)
			_action_type = request.type
			_root_incomplete = true
		if _command.accepted: _last_submitted = request.duplicate(true)
		_emit("command_resolved", {"type": request.type, "accepted": _command.accepted, "reason": _command.reason, "buffered": request.buffered, "buffer_wait_ms": request.buffered_wait_ms, "action_before": row.before.action, "action_after": row.after.action}, context)
		if not _skill.is_empty():
			_last_skill = _skill.duplicate(true)
			context.merge({"offer_id": _skill.offer_id, "reward_id": _skill.reward_id, "root_action_id": null, "batch_id": "reward:" + _skill.reward_id}, true)
			_emit("skill_acquired", {"offer_id": _skill.offer_id, "reward_id": _skill.reward_id, "skill_id": _skill.skill_id, "count_before": _skill.count_before, "count_after": _skill.count_after, "levels_before": _skill.levels_before, "levels_after": _skill.levels_after, "tool_role": tool_roles.get(_skill.skill_id), "score_delta": row.after.total.to_int() - row.before.total.to_int(), "net_empty": row.before.pieces.size() - row.after.pieces.size(), "game_over": row.after.game_over, "created": _skill.created, "removed": _skill.removed, "P_before": _pressure(row.before), "P_after": _pressure(row.after), "batch_kind": "skill_choice"}, context)
			needs_flush = true
			if _turn != null: _turn.exclude_choice(row)
		_command = {}
	if _turn != null:
		if _skill.is_empty():
			# 目标奖励属于独立批次，行动统计停在奖励入账之前。
			var action_row: Dictionary = row.duplicate()
			if not row.get("goal_before", {}).is_empty(): action_row["after"] = row.goal_before
			_turn.consume(action_row, {})
		if row.get("stage") == "spawn": _end_turn(true)
	_facts(row)
	var goal: Dictionary = row.get("challenge", {})
	if goal.get("reason") in ["stage_passed", "challenge_completed"]:
		var before_goal: Dictionary = row.get("goal_before", _state)
		_emit("stage_goal_completed", {"result": goal, "P_before": _pressure(before_goal), "P_after": _pressure(_state), "installed_build": _state.acquired.duplicate(true), "goal_effects_implemented": true, "implemented_goal_effects": ["goal_score_bonus"]}, {"stage_id": goal.stage_id, "root_action_id": goal.root_action_id})
		var bonus: Dictionary = goal.get("goal_score", {})
		if not bonus.is_empty():
			_emit("rule_fact", {"fact": "score", "score": bonus, "batch_kind": "goal_completed"}, {"root_action_id": null, "action_id": null, "stage_id": goal.stage_id, "batch_id": "goal:" + str(goal.stage_id), "rule_event_id": bonus.event_id})
		needs_flush = true
	_skill = {}
	_emit("observation_checkpoint", observation())

func _generated_offer() -> void:
	var offer: Dictionary = _pending_offer
	_pending_offer = {}
	_offers[offer.offer_id] = true
	var levels: Dictionary = {}
	for id: String in offer.choices: levels[id] = _state.acquired.get(id, "0")
	_emit("offer_generated", {"offer_id": offer.offer_id, "reward_id": offer.reward_id, "choices": offer.choices.duplicate(), "levels": levels, "baseline_weights": offer.get("baseline_weights", {}).duplicate(true), "weights": offer.weights.duplicate(true), "targets": offer.targets.duplicate(true), "generation_order": offer.generation_order, "density": _density(), "build": _state.acquired.duplicate(true), "reward_stage": offer.reward_id, "stage": TelemetryFacts.stage(_state, _config), "P_offer": offer.get("pressure_snapshot", {}) if not offer.get("pressure_snapshot", {}).is_empty() else _pressure(_state), "rescue_multiplier": offer.get("rescue_multiplier", "1"), "offer_rules_version": offer.get("offer_rules_version"), "offer_fingerprint": RunSnapshot.digest(offer)}, {"offer_id": offer.offer_id, "reward_id": offer.reward_id})
	needs_flush = true

func _end_turn(complete: bool) -> void:
	var context: Dictionary = {"command_id": _turn.command_id, "action_id": _turn.root_action_id, "root_action_id": _turn.root_action_id, "batch_id": "action:" + _turn.root_action_id, "turn_index": _turn.before.turn}
	var payload: Dictionary = _turn.payload(complete)
	payload.merge({"action_type": _action_type, "stage_before": TelemetryFacts.stage(_turn.before, _config), "stage_after": TelemetryFacts.stage(_turn.after, _config), "P_before": _pressure(_turn.before), "P_after": _pressure(_turn.after), "q_frozen": _turn.after.action_refill_count, "spawn_skipped": _turn.created.is_empty(), "build_before": _turn.before.acquired, "build_after": _turn.after.acquired, "created_ids": _turn.created.keys(), "removed_ids": _turn.removed.keys()})
	_emit("action_resolved", payload, context)
	if complete:
		_complete_actions += 1
		_last_complete_action = _turn.root_action_id
		_root_incomplete = false
	needs_flush = true
	_turn = null

func _finish(footer: Dictionary) -> void:
	_state = footer.final.duplicate(true)
	if _turn != null: _end_turn(false)
	var ids: Array[String] = []
	ids.assign(_inputs.keys())
	for id: String in ids: resolve_input(id, "discarded", "run_ended")
	_emit("observation_interval_closed", clock.change(clock.category))
	var observed: int = 0
	for duration: int in clock.times.values(): observed += duration
	flush_pending()
	_emit("run_ended", {"status": footer.status, "reason": footer.reason, "score": footer.score, "moves": footer.moves, "activations": footer.get("activations", "0"), "actions": footer.get("actions", footer.moves), "choices": footer.choices, "times": clock.times.duplicate(), "observed_ms": observed, "active_ms": observed - clock.times.inactive, "robot_compute_ms": footer.times.robot_compute, "buffer_wait_ms": footer.times.buffer_wait, "record_complete": footer.record_complete and error.is_empty()})
	_summary = _base.duplicate(true)
	_summary.merge(events.back().payload, true)
	_summary.merge({"summary_version": "run-summary-v2", "last_observation_utc": _last_observation_utc, "requested_at_utc": Time.get_datetime_string_from_system(true), "last_complete_action_id": _last_complete_action, "complete_actions": _complete_actions, "event_count": _seq, "config": _config, "exit_observation": observation(), "final_board": _state.pieces, "end_class": TelemetryFacts.ending(footer.status)})
	ended = true
	_check(sink.close())

func _density() -> float:
	return float(_state.pieces.size()) / (_base.columns.to_int() * _base.rows.to_int())

func _emit(name: String, payload: Dictionary, context: Dictionary = {}) -> void:
	if ended or _base.is_empty(): return
	_seq += 1
	var event: Dictionary = _base.duplicate()
	event.erase("columns")
	event.erase("rows")
	event.merge({"event_id": _base.run_id + ":" + str(_seq), "telemetry_seq": str(_seq), "event_name": name, "elapsed_ms": str(clock.elapsed()), "payload": payload, "action_id": _state.action if _state.action.to_int() > 0 else null, "turn_index": _state.turn if _state.turn.to_int() > 0 else null}, true)
	event.merge(context, true)
	event["observed_at_utc"] = Time.get_datetime_string_from_system(true)
	event.payload = RunSnapshot.normalize(event.payload)
	var validation: String = TelemetrySchema.validate(event)
	if not validation.is_empty():
		_check(TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, validation))
		return
	events.append(event)
	_check((sink as LocalJsonlSink).append_validated(event) if sink is LocalJsonlSink else sink.append_event(event))
	_last_observation_utc = Time.get_datetime_string_from_system(true)

func _check(result: TelemetryWriteResult) -> void:
	if result.succeeded(): return
	if error.is_empty(): push_warning("本局分析记录不完整：" + result.reason)
	error = result.reason

func ui_location(location: String) -> void:
	if ended or _base.is_empty() or location == _ui: return
	_ui = location
	_emit("ui_observed", observation())
	needs_flush = true

func play_started() -> void:
	if ended or _play_started: return
	_play_started = true
	_emit("ui_observed", observation())
	needs_flush = true

func observation(include_board: bool = true) -> Dictionary:
	var result: Dictionary = {
		"ui": _ui, "category": clock.category, "phase": _state.get("phase"),
		"stage": TelemetryFacts.stage(_state, _config), "pressure": _pressure(_state),
		"build": _state.get("acquired", {}).duplicate(true), "offer": _state.get("offer", {}).duplicate(true),
		"pending_rewards": _state.get("pending"), "last_submitted": _last_submitted.duplicate(true),
		"last_skill": _last_skill.duplicate(true), "last_complete_action_id": _last_complete_action,
		"root_complete": not _root_incomplete, "last_input_elapsed_ms": _last_input_ms,
		"since_input_ms": clock.elapsed() - _last_input_ms, "has_accepted_action": int(_state.get("action", "0")) > 0
	}
	result["play_started"] = _play_started
	if include_board: result["board"] = _state.get("pieces", []).duplicate(true)
	return result

func heartbeat() -> void:
	if ended or _base.is_empty(): return
	_emit("observation_interval_closed", clock.change(clock.category))
	_emit("observation_checkpoint", observation(false))
	needs_flush = true

func flush_pending() -> void:
	_check(sink.flush())
	needs_flush = false

func write_summary(recorder_complete: bool) -> void:
	if not ended or not sink is LocalJsonlSink or not summary_path.is_empty(): return
	var local: LocalJsonlSink = sink as LocalJsonlSink
	if not local.created: return
	_summary["record_complete"] = recorder_complete and error.is_empty()
	_summary["data_integrity"] = "complete" if _summary.record_complete else "write_failed"
	_summary["persistence"] = local.diagnostics()
	var destination: String = local.path + ".summary.json"
	var problem: String = TelemetrySummary.write_unique(destination, _summary)
	if problem.is_empty(): summary_path = destination
	else: _check(TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, problem))

func _pressure(state: Dictionary) -> Dictionary:
	if _config.is_empty(): return {}
	var fingerprint: String = JSON.stringify(state.get("pieces", []))
	if _pressure_cache.has(fingerprint): return _pressure_cache[fingerprint]
	if _pressure_cache.size() >= 4: _pressure_cache.clear()
	var result: Dictionary = TelemetryFacts.pressure(state, int(_config.columns), int(_config.rows))
	_pressure_cache[fingerprint] = result
	return result

func _facts(row: Dictionary) -> void:
	var context: Dictionary = {"root_action_id": null if not _skill.is_empty() else _state.action, "batch_id": "reward:" + _skill.reward_id if not _skill.is_empty() else "action:" + _state.action}
	var entries: Array = row.get("events", []).duplicate()
	for birth: Dictionary in row.get("births", []):
		_emit("rule_fact", {"fact": "spawn", "piece": birth.piece}, context)
		entries.append_array(birth.events)
	for piece: Dictionary in row.get("removed", []):
		_emit("rule_fact", {"fact": "removal", "piece": piece, "cause": "consume"}, context)
	for fact: Dictionary in entries:
		var score: Dictionary = fact.score
		context["rule_event_id"] = score.get("event_id")
		_emit("rule_fact", {"fact": "resolution", "cause": fact.cause, "removed": fact.removed, "recolored": fact.recolored, "previous_colors": fact.previous_colors, "score": score, "generation": fact.generation}, context)
