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

func direct_match() -> bool:
	return _direct_match

## 驱动发现无法推进时也留下显式诊断；不伪造棋盘失败。
func report_error(reason: String) -> void:
	state.rule_error = reason
	state.phase = RunState.Phase.ERROR
	if recorder != null:
		recorder.append("Diagnostic", {"reason": reason})
		recorder.checkpoint(self)

func _init(rules: BoardRules, run_seed: int, stage_config: StageConfig = null) -> void:
	state = RunState.new(rules, run_seed)
	state.stage = StageState.new(stage_config)
	abilities = AbilityResolver.new(state)
	state.run_id = "%d-%d" % [run_seed, Time.get_ticks_usec()]

## 合法操作一次提交移动、消除和基础计分；演出不重新计算。
func move_piece(piece_id: int, target: Vector2i) -> TurnResult:
	var result: TurnResult = TurnResult.new()
	if state.phase != RunState.Phase.INPUT or state.is_game_over or (state.stage.enabled() and not state.stage.can_act()):
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
	state.stage.begin_action(state.action_id, state.ledger.get_entries().size())
	state.phase = RunState.Phase.MOVING
	result.matches = resolve_matches_at(target)
	state.valid_moves += 1
	result.direct_match = not result.matches.is_empty() and result.matches[0].cause == &"match"
	return result

func resolve_matches_at(coordinate: Vector2i) -> Array[MatchResult]:
	return _resolve_groups(state.rules.find_matches_at(coordinate))

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
		state.spawning.ensure_plan(state.spawning.next_refill_count(SPAWN_CONFIG), state.explosion, abilities.config.core_color)

func finish_game(reason: StringName = &"board_full") -> void:
	if state.is_game_over or not state.rule_error.is_empty():
		return
	state.end_reason = reason
	state.is_game_over = true
	state.phase = RunState.Phase.FINISHED

## 一枚一枚选择真实空位，出生即查线；批次不会因首枚消除提前停止。
func spawn_batch(count: int = 3) -> Array[SpawnResult]:
	var result: Array[SpawnResult] = []
	if state.is_game_over or not state.rule_error.is_empty() or count <= 0:
		return result
	state.phase = RunState.Phase.SPAWNING
	state.spawning.ensure_plan(count, state.explosion, abilities.config.core_color)
	for index: int in range(count):
		var spawn: SpawnResult = spawn_one()
		if spawn == null:
			return result
		result.append(spawn)
		if not state.rule_error.is_empty():
			return result
	check_space_after_spawning()
	return result

func spawn_one() -> SpawnResult:
	if state.is_game_over or not state.rule_error.is_empty():
		return null
	state.phase = RunState.Phase.SPAWNING
	var empty: Array[Vector2i] = state.rules.state.get_empty_coordinates()
	if empty.is_empty():
		finish_game()
		return null
	var coordinate: Vector2i = empty[state.random.randi_range(0, empty.size() - 1)]
	state.spawning.ensure_plan(1, state.explosion, abilities.config.core_color)
	var token: SpawnToken = state.spawning.consume_token()
	var core: bool = false
	if token.core_candidate:
		var has_core: bool = false
		for piece: PieceState in state.rules.state.get_snapshot():
			if piece.content_id == &"special_demolition": has_core = true
		core = not has_core
	var color: int = token.core_color if core else token.color
	var ghost: bool = false
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"space_compressor" and state.random.randf() < 0.2:
			ghost = true
			break
	var result: SpawnResult = SpawnResult.new()
	result.piece = abilities.add_core(coordinate) if core else state.rules.place_piece(coordinate, color, &"", ghost)
	result.matches = resolve_matches_at(coordinate)
	state.spawn_history.append(result)
	return result

func check_space_after_spawning() -> void:
	if not state.rule_error.is_empty():
		return
	if state.rules.state.get_empty_coordinates().is_empty():
		finish_game()

func _resolve_groups(groups: Array[BoardMatchGroup]) -> Array[MatchResult]:
	var result: Array[MatchResult] = abilities.resolve(groups)
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
	if mode == "normal": result.spawns = spawn_batch(CONFIG.initial_piece_count)
	elif mode == "fixture_f6": ExplosionDemo.populate(self)
	elif mode == "fixture_demolition": DemolitionDemo.populate(self)
	elif mode == "fixture_dye": DyeDemo.populate(self)
	else:
		state.rule_error = "unsupported_initialization"
		state.phase = RunState.Phase.ERROR
	DemolitionRules.settle(state, DemolitionRules.root_id(state))
	start_turn()
	return result

func check_rewards(score_override: int = -1) -> int:
	return 0 if state.stage.enabled() else state.progression.check_score(state, PROGRESSION, score_override)

func prepare_offer() -> SkillOffer:
	if state.pending_rewards <= 0 or state.is_game_over: return null
	enter_rewards()
	var existing: SkillOffer = state.rewards.active_offer
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var offer: SkillOffer = generator.generate(self)
	if offer == null:
		state.rule_error = generator.last_error
		state.phase = RunState.Phase.ERROR
	elif existing == null and recorder != null:
		recorder.offer(self, offer)
	return offer

func execute_command(command: RunCommand) -> CommandResult:
	var payload: Dictionary = CommandCodec.encode(command)
	if command.command_id == last_command_id and _last_result != null and payload == _last_payload:
		return _last_result
	var before: Dictionary = RunSnapshot.capture(self)
	var result: CommandResult = CommandResult.new()
	if command.run_id != state.run_id: result.reason = "wrong_run"
	elif command.command_id <= last_command_id or command.command_id <= 0: result.reason = "stale_command"
	elif command.expected_action_id != state.action_id: result.reason = "stale_action"
	elif not state.rule_error.is_empty(): result.reason = "rule_error"
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
	elif command is DetonateCoreCommand:
		var detonate: DetonateCoreCommand = command as DetonateCoreCommand
		var piece: PieceState = state.rules.state.get_piece(detonate.piece_id)
		if state.phase != RunState.Phase.INPUT or state.is_game_over or (state.stage.enabled() and not state.stage.can_act()): result.reason = "busy"
		elif state.explosion.level(&"core_manual_detonation") == 0: result.reason = "manual_not_installed"
		elif piece == null or piece.content_id != &"special_demolition": result.reason = "invalid_core"
		else:
			result.reason = abilities.validation_error(1)
			if result.reason.is_empty():
				state.action_id += 1
				state.rule_action_id = state.action_id
				turn_action_id = state.action_id
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
		if offer == null or choice.reward_id != offer.reward_id: result.reason = "stale_reward"
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
	if recorder != null: recorder.command(self, command, result, before)
	return result

## 每次仅越过一个安全阶段；机器人直接确认，真人先等演出。
func advance() -> RunStepResult:
	var result: RunStepResult = RunStepResult.new()
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
			if should_spawn(_direct_match): result.spawns = spawn_batch(state.spawning.consume_refill_count(SPAWN_CONFIG))
			result.matches = DemolitionRules.settle(state, turn_action_id)
			check_rewards()
			result.challenge = _settle_stage()
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
func _settle_stage() -> StageResult:
	if not state.stage.enabled() or not state.rule_error.is_empty(): return null
	var result: StageResult = state.stage.settle(state.ledger.get_entries(), state.rules.state.get_empty_coordinates().is_empty(), state.rewards.consumed_count + 1)
	if result == null: return null
	if result.reason == &"stage_passed":
		state.pending_rewards += 1
		state.phase = RunState.Phase.REWARDS
	else: finish_game(result.reason)
	return result
