class_name RunController
extends RefCounted

var state: RunState
var abilities: AbilityResolver

func _init(rules: BoardRules, run_seed: int) -> void:
	state = RunState.new(rules, run_seed)
	abilities = AbilityResolver.new(state)

## 合法操作一次提交移动、消除和基础计分；演出不重新计算。
func move_piece(piece_id: int, target: Vector2i) -> TurnResult:
	var result: TurnResult = TurnResult.new()
	if state.phase != RunState.Phase.INPUT or state.is_game_over:
		result.move = BoardMoveResult.new()
		result.move.failure = BoardMoveResult.Failure.BUSY
		return result
	result.move = state.rules.move_piece(piece_id, target)
	if not result.move.is_valid():
		return result
	state.action_id += 1
	state.phase = RunState.Phase.MOVING
	result.matches = resolve_matches_at(target)
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

func should_spawn(direct_match: bool) -> bool:
	return not direct_match or state.rules.state.get_piece_count() == 0

func start_turn() -> void:
	if state.is_game_over or not state.rule_error.is_empty():
		return
	state.turn_count += 1
	state.phase = RunState.Phase.INPUT

func finish_game() -> void:
	if not state.rule_error.is_empty():
		return
	state.is_game_over = true
	state.phase = RunState.Phase.FINISHED

## 一枚一枚选择真实空位，出生即查线；批次不会因首枚消除提前停止。
func spawn_batch(count: int = 3) -> Array[SpawnResult]:
	var result: Array[SpawnResult] = []
	if state.is_game_over or not state.rule_error.is_empty() or count <= 0:
		return result
	state.phase = RunState.Phase.SPAWNING
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
	var color: int = state.random.randi_range(0, 4)
	var ghost: bool = false
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"space_compressor" and state.random.randf() < 0.2:
			ghost = true
			break
	var result: SpawnResult = SpawnResult.new()
	result.piece = state.rules.place_piece(coordinate, color, &"", ghost)
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
	return result
