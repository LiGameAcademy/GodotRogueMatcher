class_name RunController
extends RefCounted

var state: RunState
var abilities: AbilityResolver
const PROGRESSION: ProgressionConfig = preload("res://gameplay/progression/content/progression_config.tres")
const CONFIG: RunConfig = preload("res://gameplay/run/run_config.tres")
const SPAWN_CONFIG: SpawnConfig = preload("res://gameplay/run/spawn_config.tres")
var recorder: RunRecorder
var continuation: StringName = &"idle"
var last_command_id: int = 0
var initialization: String = "normal"
var _direct_match: bool = false
var turn_action_id: int = 0
var _last_payload: Dictionary = {}
var _last_result: CommandResult
var action_refill_count: int = 0
var _retired: bool = false
var prototype_profile: StringName = &""
const PROTOTYPE_PROFILE: StringName = &"shape-unlock-fixture-v1"
const PLUS_PROFILE: StringName = &"shape-unlock-plus-fixture-v1"
const PLUS_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_plus", "fixture_shape_unlock_plus_empty", "fixture_shape_unlock_plus_two_rewards"]
const SHAPE_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock", "fixture_shape_unlock_empty", "fixture_shape_unlock_chain", "fixture_shape_unlock_t", "fixture_shape_unlock_t_empty", "fixture_shape_unlock_t_two_rewards"]

func is_retired() -> bool:
	return _retired

## Closing a scene/run invalidates its continuation and any queued descendants.
func retire() -> void:
	if _retired: return
	_retired = true
	abilities.abandon_held_blasts()
	state.ability_events.close()

func can_continue_challenge() -> bool:
	return state.is_game_over and state.end_reason == &"challenge_completed" and state.rule_error.is_empty() and state.stage.can_continue() and not state.rules.state.get_empty_coordinates().is_empty() and (recorder == null or not recorder.ended)

func direct_match() -> bool:
	return _direct_match

## 驱动发现无法推进时也留下显式诊断；不伪造棋盘失败。
func report_error(reason: String) -> void:
	state.rule_error = reason
	state.phase = RunState.Phase.ERROR
	if recorder != null:
		recorder.append("Diagnostic", {"reason": reason})
		recorder.checkpoint(self)

func _init(rules: BoardRules, run_seed: int, stage_config: StageConfig = null, profile: StringName = &"") -> void:
	assert(profile in [&"", PROTOTYPE_PROFILE, PLUS_PROFILE])
	prototype_profile = profile
	state = RunState.new(rules, run_seed)
	state.stage = StageState.new(stage_config, state.ledger)
	abilities = AbilityResolver.new(state)
	state.run_id = "%d-%d-%d-%d" % [run_seed, OS.get_process_id(), int(Time.get_unix_time_from_system() * 1000000.0), Time.get_ticks_usec()]

## 合法操作一次提交移动、消除和基础计分；演出不重新计算。
func move_piece(piece_id: int, target: Vector2i) -> TurnResult:
	var result: TurnResult = TurnResult.new()
	if _retired or state.phase != RunState.Phase.INPUT or state.is_game_over or (state.stage.enabled() and not state.stage.can_act()):
		result.move = BoardMoveResult.new()
		result.move.failure = BoardMoveResult.Failure.BUSY
		return result
	result.move = state.rules.validate_move(piece_id, target)
	if not result.move.is_valid(): return result
	if not abilities.validation_error(1).is_empty():
		result.move.failure = BoardMoveResult.Failure.RULE_REJECTED
		return result
	result.move = state.rules.move_piece(piece_id, target)
	if not result.move.is_valid():
		return result
	state.action_id += 1
	state.rule_action_id = state.action_id
	turn_action_id = state.action_id
	_freeze_action_refill()
	state.stage.begin_action(state.action_id, state.ledger.get_entries().size())
	state.phase = RunState.Phase.MOVING
	result.matches = resolve_matches_at(target, false, &"direct_move")
	state.valid_moves += 1
	result.direct_match = not result.matches.is_empty() and result.matches[0].cause == &"match"
	return result

func resolve_matches_at(coordinate: Vector2i, hold_descendants: bool = false, match_source: StringName = &"") -> Array[MatchResult]:
	return _resolve_groups(state.rules.find_matches_at(coordinate), hold_descendants, match_source)

func resolve_all_matches() -> Array[MatchResult]:
	return _resolve_groups(state.rules.find_matches())

func enter_rewards() -> void:
	if not state.is_game_over and state.rule_error.is_empty():
		state.phase = RunState.Phase.REWARDS

func end_turn() -> void:
	if not state.is_game_over and state.rule_error.is_empty():
		state.phase = RunState.Phase.TURN_END
		DemolitionRules.relay(abilities)

func should_spawn(direct_match: bool) -> bool:
	return not direct_match or state.rules.state.get_piece_count() == 0

func start_turn() -> void:
	if state.is_game_over or not state.rule_error.is_empty():
		return
	state.turn_count += 1
	prepare_spawn_plan()
	state.phase = RunState.Phase.INPUT

func prepare_spawn_plan() -> void:
	if not state.is_game_over and state.rule_error.is_empty():
		state.spawning.ensure_plan(state.next_refill_count(), state.explosion, state.line_clear)

## 在阶段u推进前冻结已预告批次；本行动越线不会改变其补棋代价。
func _freeze_action_refill() -> void:
	action_refill_count = state.next_refill_count()
	state.spawning.ensure_plan(action_refill_count, state.explosion, state.line_clear)

func finish_game(reason: StringName = &"board_full") -> void:
	if state.is_game_over or not state.rule_error.is_empty():
		return
	state.end_reason = reason
	state.is_game_over = true
	state.phase = RunState.Phase.FINISHED

## 一枚一枚选择真实空位，出生即查线；批次不会因首枚消除提前停止。
func spawn_batch(count: int = 3, source: StringName = &"normal", batch_id: int = 0) -> Array[SpawnResult]:
	var result: Array[SpawnResult] = []
	if state.is_game_over or not state.rule_error.is_empty() or count <= 0:
		return result
	state.phase = RunState.Phase.SPAWNING
	state.spawning.ensure_plan(count, state.explosion, state.line_clear)
	for index: int in range(count):
		var spawn: SpawnResult = spawn_one(source, batch_id)
		if spawn == null:
			return result
		result.append(spawn)
		if not state.rule_error.is_empty():
			return result
	check_space_after_spawning()
	return result

func spawn_one(source: StringName = &"normal", batch_id: int = 0) -> SpawnResult:
	if state.is_game_over or not state.rule_error.is_empty():
		return null
	state.phase = RunState.Phase.SPAWNING
	var empty: Array[Vector2i] = state.rules.state.get_empty_coordinates()
	if empty.is_empty():
		finish_game()
		return null
	var coordinate: Vector2i = empty[state.random.randi_range(0, empty.size() - 1)]
	state.spawning.ensure_plan(1, state.explosion, state.line_clear)
	var token: SpawnToken = state.spawning.consume_token()
	var core: bool = false
	if token.core_candidate:
		var has_core: bool = false
		for piece: PieceState in state.rules.state.get_snapshot():
			if piece.content_id == &"special_demolition": has_core = true
		core = not has_core
	var color: int = token.color
	var ghost: bool = false
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"space_compressor" and state.random.randf() < 0.2:
			ghost = true
			break
	var result: SpawnResult = SpawnResult.new()
	result.source = source
	result.batch_id = batch_id
	if core:
		result.piece = abilities.add_core(coordinate, color)
	elif token.line_axis >= 0:
		result.piece = abilities.add_line_piece(token.line_axis, coordinate, color)
	else:
		result.piece = state.rules.place_piece(coordinate, color, &"", ghost)
	result.matches = resolve_matches_at(coordinate, false, &"recovery_birth" if source == &"empty_recovery" else &"birth")
	state.spawn_history.append(result)
	return result

func check_space_after_spawning() -> void:
	if not state.rule_error.is_empty():
		return
	if state.rules.state.get_empty_coordinates().is_empty():
		finish_game()

func _resolve_groups(groups: Array[BoardMatchGroup], hold_descendants: bool = false, match_source: StringName = &"") -> Array[MatchResult]:
	var result: Array[MatchResult] = abilities.resolve(groups, hold_descendants, match_source)
	if not abilities.last_error.is_empty():
		state.rule_error = abilities.last_error
		state.phase = RunState.Phase.ERROR
	check_rewards()
	return result

## 初始化与自动阶段也使用规则结果，UI只选择何时请求下一步。
func initialize(mode: String = "normal") -> RunStepResult:
	initialization = mode
	var result: RunStepResult = RunStepResult.new()
	result.kind = &"initial"
	if state.stage.enabled() and not state.stage.config.validation_error().is_empty():
		report_error(state.stage.config.validation_error())
		return result
	if (mode in SHAPE_INITIALIZATIONS and prototype_profile == PROTOTYPE_PROFILE) or (mode in PLUS_INITIALIZATIONS and prototype_profile == PLUS_PROFILE):
		var demo: Script = load("res://gameplay/skills/debug/shape_unlock_demo.gd") as Script
		demo.populate(self, mode)
	elif mode == "normal": result.spawns = spawn_batch(CONFIG.initial_piece_count)
	elif mode == "fixture_f6": ExplosionDemo.populate(self)
	elif mode == "fixture_demolition": DemolitionDemo.populate(self)
	elif mode == "fixture_dye": DyeDemo.populate(self)
	elif mode == "fixture_line": LineClearDemo.populate(self)
	elif mode == "fixture_line_score": LineClearDemo.populate(self, false, true)
	elif mode == "fixture_line_span": LineClearDemo.populate(self, true)
	elif mode == "fixture_line_cross": LineClearDemo.populate_cross(self)
	elif mode == "fixture_manual_limit": LineClearDemo.populate_manual_limit(self)
	elif mode == "fixture_transform": TransformationDemo.populate(self)
	else:
		state.rule_error = "unsupported_initialization"
		state.phase = RunState.Phase.ERROR
	DemolitionRules.settle(state, DemolitionRules.root_id(state))
	start_turn()
	if state.pending_rewards > 0: enter_rewards()
	return result

func check_rewards(score_override: int = -1) -> int:
	return 0 if state.stage.enabled() else state.progression.check_score(state, PROGRESSION, score_override)

func prepare_offer(record_offer: bool = true, generator: SkillOfferGenerator = null) -> SkillOffer:
	if state.pending_rewards <= 0 or state.is_game_over or not state.rule_error.is_empty(): return null
	enter_rewards()
	var existing: SkillOffer = state.rewards.active_offer
	var source: SkillOfferGenerator = generator if generator != null else SkillOfferGenerator.new()
	if generator == null: source.set_catalog(offer_catalog())
	var offer: SkillOffer = RewardOfferRules.prepare(self, source)
	if offer != null and offer != existing and recorder != null and record_offer:
		recorder.offer(self, offer)
	return offer

## Explicit fixture profile only; production never installs test recipes.
func offer_catalog() -> Array[SkillDefinition]:
	if prototype_profile in [PROTOTYPE_PROFILE, PLUS_PROFILE]:
		var demo: Script = load("res://gameplay/skills/debug/shape_unlock_demo.gd") as Script
		return demo.plus_catalog() if prototype_profile == PLUS_PROFILE else demo.catalog()
	return SkillOfferGenerator.new().catalog()

func execute_command(command: RunCommand) -> CommandResult:
	if _retired:
		var closed: CommandResult = CommandResult.new()
		closed.reason = "run_closed"
		return closed
	var payload: Dictionary = CommandCodec.encode(command)
	if command.command_id == last_command_id and _last_result != null and payload == _last_payload:
		return _last_result
	var before: Dictionary = RunSnapshot.capture(self)
	var result: CommandResult = CommandResult.new()
	if command.run_id != state.run_id: result.reason = "wrong_run"
	elif command.command_id <= last_command_id or command.command_id <= 0: result.reason = "stale_command"
	elif command.expected_action_id != state.action_id: result.reason = "stale_action"
	elif not state.rule_error.is_empty(): result.reason = "rule_error"
	elif command is ContinueChallengeCommand:
		if not can_continue_challenge(): result.reason = "cannot_continue_challenge"
		else:
			state.stage.continue_challenge()
			state.is_game_over = false
			state.end_reason = &""
			state.pending_rewards += 1
			state.phase = RunState.Phase.REWARDS
			prepare_spawn_plan()
			result.accepted = true
	elif command is MovePieceCommand:
		var move: MovePieceCommand = command as MovePieceCommand
		result.reason = abilities.validation_error(1)
		if result.reason.is_empty():
			result.turn = move_piece(move.piece_id, move.target)
			result.accepted = result.turn.move.is_valid() and state.rule_error.is_empty()
			if result.accepted:
				_direct_match = result.turn.direct_match
				continuation = &"before_end"
			else: result.reason = str(BoardMoveResult.Failure.keys()[result.turn.move.failure])
	elif command is DetonateCoreCommand or command is ActivateLineCommand:
		var line: bool = command is ActivateLineCommand
		var piece_id: int = (command as ActivateLineCommand).piece_id if line else (command as DetonateCoreCommand).piece_id
		var piece: PieceState = state.rules.state.get_piece(piece_id)
		if state.phase != RunState.Phase.INPUT or state.is_game_over or (state.stage.enabled() and not state.stage.can_act()): result.reason = "busy"
		elif (state.line_clear.level(&"line_manual_clear") if line else state.explosion.level(&"core_manual_detonation")) == 0: result.reason = "manual_not_installed"
		elif piece == null or (not LineClearState.is_line_piece(piece.content_id) if line else piece.content_id != &"special_demolition"):
			result.reason = "invalid_line_piece" if line else "invalid_core"
		elif line and not state.line_clear.instances.has(piece_id): result.reason = "missing_line_ability"
		elif ManualActivationRules.remaining(state, line) == 0: result.reason = "manual_uses_exhausted"
		else:
			result.reason = abilities.validation_error(1)
			if result.reason.is_empty():
				ManualActivationRules.consume(state, line)
				state.action_id += 1
				state.rule_action_id = state.action_id
				turn_action_id = state.action_id
				_freeze_action_refill()
				state.stage.begin_action(state.action_id, state.ledger.get_entries().size())
				state.activations += 1
				state.phase = RunState.Phase.MOVING
				result.turn = TurnResult.new()
				result.turn.removed.append(piece.copy())
				result.turn.matches = abilities.resolve_removal(result.turn.removed, &"consume")
				result.accepted = true
				_direct_match = false
				continuation = &"before_end"
	elif command is ChooseSkillCommand:
		var choice: ChooseSkillCommand = command as ChooseSkillCommand
		var offer: SkillOffer = state.rewards.active_offer
		if offer == null or choice.reward_id != offer.reward_id or choice.offer_id != offer.offer_id: result.reason = "stale_reward"
		else:
			var current: SkillOffer = prepare_offer(false)
			if current == null: result.reason = state.rule_error
			elif current != offer:
				result.offer = current
				result.reason = "offer_replaced"
			else:
				result.skill = SkillRules.apply(self, choice.offer_id, choice.skill_id, choice.selected_color)
				result.accepted = result.skill.success
				result.reason = result.skill.error
			if result.accepted: prepare_spawn_plan()
			check_rewards()
			if result.accepted and state.rules.state.get_empty_coordinates().is_empty():
				if continuation != &"idle": result.skill.matches.append_array(DemolitionRules.settle(state, turn_action_id))
				finish_game()
	else: result.reason = "unknown_command"
	result.rule_error = not state.rule_error.is_empty()
	if result.rule_error: result.reason = state.rule_error
	if command.command_id > last_command_id:
		last_command_id = command.command_id
		_last_payload = payload.duplicate(true)
		_last_result = result
	if recorder != null:
		recorder.command(self, command, result, before)
		if result.offer != null: recorder.offer(self, result.offer, "all_candidates_unavailable")
	return result

## 每次仅越过一个安全阶段；机器人直接确认，真人先等演出。
func advance() -> RunStepResult:
	var result: RunStepResult = RunStepResult.new()
	if _retired:
		result.kind = &"closed"
		return result
	if not state.rule_error.is_empty():
		result.kind = &"error"
		return result
	if state.is_game_over:
		result.kind = &"finished"
		return result
	check_rewards()
	if state.pending_rewards > 0:
		result.kind = &"offer"
		result.offer = prepare_offer()
		return result
	if continuation in [&"idle", &"after_spawn"]:
		var recovery: RunStepResult = EmptyBoardRecovery.advance(self)
		if recovery != null:
			if recorder != null: recorder.step(self, recovery)
			return recovery
	if state.stage.awaiting_reward: state.stage.start_next()
	match continuation:
		&"before_end":
			state.rule_action_id = turn_action_id
			end_turn()
			continuation = &"after_end"
			result.kind = &"end_turn"
		&"after_end":
			state.rule_action_id = turn_action_id
			continuation = &"after_spawn"
			result.kind = &"spawn"
			if should_spawn(_direct_match):
				var count: int = action_refill_count
				if state.stage.enabled(): state.spawning.consume_refill_modifiers()
				else: count = state.spawning.consume_refill_count(SPAWN_CONFIG)
				result.spawns = spawn_batch(count)
			result.matches = DemolitionRules.settle(state, turn_action_id)
			check_rewards()
			result.challenge = _settle_stage(result)
		&"after_spawn":
			continuation = &"idle"
			start_turn()
			result.kind = &"input"
		_:
			state.phase = RunState.Phase.INPUT
			result.kind = &"input"
	if recorder != null: recorder.step(self, result)
	return result

## 完整根行动收束的唯一阶段结算入口，演出只消费结果。
func _settle_stage(step: RunStepResult) -> StageResult:
	if not state.stage.enabled() or not state.rule_error.is_empty(): return null
	var result: StageResult = state.stage.settle(state.ledger.get_entries(), state.rules.state.get_empty_coordinates().is_empty(), state.rewards.consumed_count + 1)
	if result == null: return null
	if result.reason in [&"stage_passed", &"challenge_completed"]:
		step.goal_before = RunSnapshot.capture(self)
		GoalCompletionRules.resolve(state, result)
	if result.reason == &"stage_passed":
		state.pending_rewards += 1
		state.phase = RunState.Phase.REWARDS
		prepare_spawn_plan()
	else: finish_game(result.reason)
	return result
