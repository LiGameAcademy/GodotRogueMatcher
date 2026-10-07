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

func _init(destination: TelemetrySink, session_id: String, timer: Callable = Callable()) -> void:
	sink = destination
	_session_id = session_id
	clock = TelemetryClock.new(timer)

## 只消费33冻结后的事实，不持有RunController、Node或随机对象。
func observe_record(row: Dictionary) -> void:
	if ended: return
	match row.kind:
		"Header": _start(row)
		"CommandAttempt": _command = row.duplicate(true)
		"SkillAcquired": _skill = row.duplicate(true)
		"Offer": _pending_offer = row.offer.duplicate(true)
		"Checkpoint":
			_state = row.state.duplicate(true)
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
	_base = {"schema_version": TelemetrySchema.VERSION, "run_id": header.run_id, "session_id": _session_id, "rule_version": header.rules_version, "content_version": header.content_version, "offer_version": header.offer_version, "build_id": header.build, "config_hash": header.config_hash, "source": header.source, "initialization": header.initialization, "action_id": null, "turn_index": null, "command_id": null, "experiment_id": header.metadata.get("experiment_id"), "variant_id": header.metadata.get("variant_id"), "strategy_version": header.metadata.get("strategy"), "columns": header.config.columns, "rows": header.config.rows}
	# 初始化规则与文件创建不冒充玩家观察区间。
	var bot_config: Dictionary = header.metadata.get("bot_config", {})
	_base["bot_config_hash"] = null if bot_config.is_empty() else RunSnapshot.digest(bot_config)
	clock = TelemetryClock.new(clock.time_source())
	var companions: int = 0
	for piece: Dictionary in _state.pieces:
		if not piece.content_id.is_empty(): companions += 1
	_emit("run_started", {"columns": header.config.columns, "rows": header.config.rows, "ordinary": _state.pieces.size() - companions, "companions": companions, "score": _state.total})

func _resolved(row: Dictionary) -> void:
	_state = row.after.duplicate(true)
	if row.has("command_id") and not _command.is_empty():
		var request: Dictionary = _command.command
		var context: Dictionary = {"command_id": request.command_id}
		if _command.accepted and request.type in ["move", "detonate"]:
			_turn = TelemetryTurn.new(row.before, request.command_id, row.after.action)
		_emit("command_resolved", {"type": request.type, "accepted": _command.accepted, "reason": _command.reason, "buffered": request.buffered, "buffer_wait_ms": request.buffered_wait_ms, "action_before": row.before.action, "action_after": row.after.action}, context)
		if not _skill.is_empty():
			_emit("skill_acquired", {"offer_id": _skill.offer_id, "skill_id": _skill.skill_id, "count_before": _skill.count_before, "count_after": _skill.count_after, "tool_role": tool_roles.get(_skill.skill_id), "score_delta": row.after.total.to_int() - row.before.total.to_int(), "net_empty": row.before.pieces.size() - row.after.pieces.size(), "game_over": row.after.game_over}, context)
		_command = {}
	if _turn != null:
		_turn.consume(row, _skill)
		if row.get("stage") == "input": _end_turn(true)
	_skill = {}

func _generated_offer() -> void:
	var offer: Dictionary = _pending_offer
	_pending_offer = {}
	_offers[offer.offer_id] = true
	var levels: Dictionary = {}
	for id: String in offer.choices: levels[id] = _state.acquired.get(id, "0")
	_emit("offer_generated", {"offer_id": offer.offer_id, "reward_id": offer.reward_id, "choices": offer.choices.duplicate(), "levels": levels, "weights": offer.weights.duplicate(true), "density": _density(), "build": _state.acquired.duplicate(true), "reward_stage": offer.reward_id})

func _end_turn(complete: bool) -> void:
	_emit("turn_resolved", _turn.payload(complete), {"command_id": _turn.command_id, "action_id": _turn.root_action_id, "turn_index": _turn.before.turn})
	_turn = null

func _finish(footer: Dictionary) -> void:
	_state = footer.final.duplicate(true)
	if _turn != null: _end_turn(footer.status == "completed")
	var ids: Array[String] = []
	ids.assign(_inputs.keys())
	for id: String in ids: resolve_input(id, "discarded", "run_ended")
	_emit("observation_interval_closed", clock.change(clock.category))
	var observed: int = 0
	for duration: int in clock.times.values(): observed += duration
	_emit("run_ended", {"status": footer.status, "reason": footer.reason, "score": footer.score, "moves": footer.moves, "activations": footer.get("activations", "0"), "actions": footer.get("actions", footer.moves), "choices": footer.choices, "times": clock.times.duplicate(), "observed_ms": observed, "active_ms": observed - clock.times.inactive, "robot_compute_ms": footer.times.robot_compute, "buffer_wait_ms": footer.times.buffer_wait, "record_complete": footer.record_complete and error.is_empty()})
	ended = true
	_check(sink.close())

func _density() -> float:
	return float(_state.pieces.size()) / (_base.columns.to_int() * _base.rows.to_int())

func _emit(name: String, payload: Dictionary, context: Dictionary = {}) -> void:
	if ended or _base.is_empty(): return
	_seq += 1
	var event: Dictionary = _base.duplicate(true)
	event.erase("columns")
	event.erase("rows")
	event.merge({"event_id": _base.run_id + ":" + str(_seq), "telemetry_seq": str(_seq), "event_name": name, "elapsed_ms": str(clock.elapsed()), "payload": payload.duplicate(true), "action_id": _state.action if _state.action.to_int() > 0 else null, "turn_index": _state.turn if _state.turn.to_int() > 0 else null}, true)
	event.merge(context, true)
	event = RunSnapshot.normalize(event)
	var validation: String = TelemetrySchema.validate(event)
	if not validation.is_empty():
		_check(TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, validation))
		return
	events.append(event.duplicate(true))
	_check(sink.append_event(event.duplicate(true)))
	_check(sink.flush())

func _check(result: TelemetryWriteResult) -> void:
	if result.succeeded(): return
	if error.is_empty(): push_warning("本局分析记录不完整：" + result.reason)
	error = result.reason
