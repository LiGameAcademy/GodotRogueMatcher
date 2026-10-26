class_name RunController
extends RefCounted

## Owns deterministic run progression, command validation and rule-result sequencing.
## Presentation requests advance explicitly; no UI node or animation controls rule outcomes.

const PROGRESSION: ProgressionConfig = preload("res://gameplay/progression/content/progression_config.tres")
const CONFIG: RunConfig = preload("res://gameplay/run/run_config.tres")
const SPAWN_CONFIG: SpawnConfig = preload("res://gameplay/run/spawn_config.tres")
const PROTOTYPE_PROFILE: StringName = &"shape-unlock-fixture-v1"
const SCREENING_PROFILE: StringName = &"screening-free-v1"
const SCREENING_FIXED_PROFILE: StringName = &"screening-fixed-v1"
const MIXED_PROFILE: StringName = &"shape-mixed-fixture-v1"
const SQUARE_PROFILE: StringName = &"shape-unlock-square-fixture-v1"
const SQUARE_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_square", "fixture_shape_unlock_square_empty", "fixture_shape_unlock_square_two_rewards", "fixture_shape_unlock_square_center", "fixture_shape_square_move"]
const RING_PROFILE: StringName = &"shape-unlock-ring-fixture-v1"
const RING_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_ring", "fixture_shape_unlock_ring_empty", "fixture_shape_unlock_ring_two_rewards", "fixture_shape_unlock_ring_center", "fixture_shape_ring_move"]
const U_PROFILE: StringName = &"shape-unlock-u-fixture-v1"
const U_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_u", "fixture_shape_unlock_u_empty", "fixture_shape_unlock_u_two_rewards", "fixture_shape_unlock_u_rotated", "fixture_shape_u_move"]
const ZS_PROFILE: StringName = &"shape-unlock-zs-fixture-v1"
const ZS_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_zs", "fixture_shape_unlock_zs_empty", "fixture_shape_unlock_zs_two_rewards", "fixture_shape_unlock_zs_mirror", "fixture_shape_zs_move"]
const X_PROFILE: StringName = &"shape-unlock-x-fixture-v1"
const X_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_x", "fixture_shape_unlock_x_empty", "fixture_shape_unlock_x_two_rewards"]
const PLUS_PROFILE: StringName = &"shape-unlock-plus-fixture-v1"
const PLUS_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock_plus", "fixture_shape_unlock_plus_empty", "fixture_shape_unlock_plus_two_rewards"]
const SHAPE_INITIALIZATIONS: Array[String] = ["fixture_shape_unlock", "fixture_shape_unlock_empty", "fixture_shape_unlock_chain", "fixture_shape_unlock_t", "fixture_shape_unlock_t_empty", "fixture_shape_unlock_t_two_rewards"]

## Shared run state and services; mutation belongs to this controller and rule collaborators.
var state: RunState
var abilities: AbilityResolver
var recorder: RunRecorder
var continuation: StringName = &"idle"
var last_command_id: int = 0
var initialization: String = "normal"
var turn_action_id: int = 0
var action_refill_count: int = 0
var prototype_profile: StringName = &""

var _direct_match: bool = false
var _last_payload: Dictionary = {}
var _last_result: CommandResult
var _retired: bool = false

## Reports whether the owning scene has permanently closed this run.
func is_retired() -> bool:
	return _retired

## Closing a scene/run invalidates its continuation and any queued descendants.
func retire() -> void:
	if _retired: return
	_retired = true
	abilities.abandon_held_blasts()
	state.ability_events.close()

## Reports whether the completed challenge can continue without replacing this run.
func can_continue_challenge() -> bool:
	return state.is_game_over and state.end_reason == &"challenge_completed" and state.rule_error.is_empty() and state.stage.can_continue() and not state.rules.state.get_empty_coordinates().is_empty() and (recorder == null or not recorder.ended)

## Returns whether the current root action produced a direct match.
func direct_match() -> bool:
	return _direct_match

## Records a driver failure as a rule diagnostic without inventing a board loss.
func report_error(reason: String) -> void:
	state.rule_error = reason
	state.phase = RunState.Phase.ERROR
	if recorder != null:
		recorder.append("Diagnostic", {"reason": reason})
		recorder.checkpoint(self)

# Construction stays after lightweight queries to preserve resource typing
# in the existing cyclic AbilityResolver load graph (Godot 4.7.2).
func _init(rules: BoardRules, run_seed: int, stage_config: StageConfig = null, profile: StringName = &"") -> void:
	assert(profile in [&"", PROTOTYPE_PROFILE, PLUS_PROFILE, X_PROFILE, ZS_PROFILE, U_PROFILE, RING_PROFILE, SQUARE_PROFILE, MIXED_PROFILE, SCREENING_PROFILE, SCREENING_FIXED_PROFILE])
	prototype_profile = profile
	state = RunState.new(rules, run_seed)
	state.stage = StageState.new(stage_config, state.ledger)
	abilities = AbilityResolver.new(state)
	state.run_id = "%d-%d-%d-%d" % [run_seed, OS.get_process_id(), int(Time.get_unix_time_from_system() * 1000000.0), Time.get_ticks_usec()]

## Commits a legal move, matching and base score once; presentation consumes the result.
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

## Resolves groups containing the landing entity; optional descendant holding preserves order.
func resolve_matches_at(coordinate: Vector2i, hold_descendants: bool = false, match_source: StringName = &"") -> Array[MatchResult]:
	return _resolve_groups(state.rules.find_matches_at(coordinate), hold_descendants, match_source)

## Scans and resolves enabled groups against the current authoritative board.
func resolve_all_matches() -> Array[MatchResult]:
	return _resolve_groups(state.rules.find_matches())

## Enters reward waiting only while the run remains healthy and active.
func enter_rewards() -> void:
	if not state.is_game_over and state.rule_error.is_empty():
		state.phase = RunState.Phase.REWARDS

## Commits turn-end phase and relay effects without awaiting presentation.
func end_turn() -> void:
	if not state.is_game_over and state.rule_error.is_empty():
		state.phase = RunState.Phase.TURN_END
		DemolitionRules.relay(abilities)

## Refills after a nonmatch or an empty board, including a clearing direct match.
func should_spawn(direct_match: bool) -> bool:
	return not direct_match or state.rules.state.get_piece_count() == 0

## Starts the next input turn and ensures its announced spawn plan.
func start_turn() -> void:
	if state.is_game_over or not state.rule_error.is_empty():
		return
	state.turn_count += 1
	prepare_spawn_plan()
	state.phase = RunState.Phase.INPUT

## Preserves an existing plan or creates the next announced refill.
func prepare_spawn_plan() -> void:
	if not state.is_game_over and state.rule_error.is_empty():
		state.spawning.ensure_plan(state.next_refill_count(), state.explosion, state.line_clear)

## Closes an active healthy run with an explicit end reason.
func finish_game(reason: StringName = &"board_full") -> void:
	if state.is_game_over or not state.rule_error.is_empty():
		return
	state.end_reason = reason
	state.is_game_over = true
	state.phase = RunState.Phase.FINISHED

## Chooses live empty cells one by one; matches do not truncate a valid batch.
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

## Consumes one planned token and resolves birth matches at its chosen live empty cell.
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

## Ends a healthy run if no empty cell remains after the batch.
func check_space_after_spawning() -> void:
	if not state.rule_error.is_empty():
		return
	if state.rules.state.get_empty_coordinates().is_empty():
		finish_game()

## Initializes rule state and returns committed births for presentation or headless drivers.
func initialize(mode: String = "normal") -> RunStepResult:
	initialization = mode
	var result: RunStepResult = RunStepResult.new()
	result.kind = &"initial"
	if state.stage.enabled() and not state.stage.config.validation_error().is_empty():
		report_error(state.stage.config.validation_error())
		return result
	if mode in ScreeningDeck.modes() and prototype_profile == SCREENING_FIXED_PROFILE:
		ScreeningDeck.populate(self, mode)
	elif mode in MixedTemplateDemo.MODES and prototype_profile == MIXED_PROFILE:
		MixedTemplateDemo.populate(self, mode)
	elif (mode in SHAPE_INITIALIZATIONS and prototype_profile == PROTOTYPE_PROFILE) or (mode in PLUS_INITIALIZATIONS and prototype_profile == PLUS_PROFILE) or (mode in X_INITIALIZATIONS and prototype_profile == X_PROFILE) or (mode in ZS_INITIALIZATIONS and prototype_profile == ZS_PROFILE) or (mode in U_INITIALIZATIONS and prototype_profile == U_PROFILE) or (mode in RING_INITIALIZATIONS and prototype_profile == RING_PROFILE) or (mode in SQUARE_INITIALIZATIONS and prototype_profile == SQUARE_PROFILE):
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

## Checks classic score milestones; stage mode owns its reward schedule.
func check_rewards(score_override: int = -1) -> int:
	return 0 if state.stage.enabled() else state.progression.check_score(state, PROGRESSION, score_override)

## Returns the current valid offer, recording only newly generated offers when requested.
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
	if prototype_profile == SCREENING_FIXED_PROFILE: return ScreeningDeck.fixed_catalog()
	if prototype_profile in [PROTOTYPE_PROFILE, PLUS_PROFILE, X_PROFILE, ZS_PROFILE, U_PROFILE, RING_PROFILE, SQUARE_PROFILE, MIXED_PROFILE]:
		var demo: Script = load("res://gameplay/skills/debug/shape_unlock_demo.gd") as Script
		if prototype_profile == MIXED_PROFILE: return MixedTemplateDemo.catalog()
		if prototype_profile == SQUARE_PROFILE: return demo.square_catalog()
		if prototype_profile == RING_PROFILE: return demo.ring_catalog()
		if prototype_profile == U_PROFILE: return demo.u_catalog()
		if prototype_profile == ZS_PROFILE: return demo.zs_catalog()
		if prototype_profile == X_PROFILE: return demo.x_catalog()
		return demo.plus_catalog() if prototype_profile == PLUS_PROFILE else demo.catalog()
	return SkillOfferGenerator.new().catalog()

## Validates run/action identity and reuses the cached result for an identical command retry.
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

## Crosses one safe phase boundary; callers decide when presentation permits the next step.
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

## Freezes the announced refill before stage progress can change its cost.
func _freeze_action_refill() -> void:
	action_refill_count = state.next_refill_count()
	state.spawning.ensure_plan(action_refill_count, state.explosion, state.line_clear)

func _resolve_groups(groups: Array[BoardMatchGroup], hold_descendants: bool = false, match_source: StringName = &"") -> Array[MatchResult]:
	var result: Array[MatchResult] = abilities.resolve(groups, hold_descendants, match_source)
	if not abilities.last_error.is_empty():
		state.rule_error = abilities.last_error
		state.phase = RunState.Phase.ERROR
	check_rewards()
	return result

## Settles a completed root action exactly once; presentation only consumes its result.
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
