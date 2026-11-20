extends RefCounted

const U: MatchShapeTemplate = preload("res://gameplay/board/matching/u_template.tres")
const L: MatchShapeTemplate = preload("res://gameplay/board/matching/l_template.tres")

static func run(u_enabled: bool = true, l_enabled: bool = false) -> RunController:
	var templates: Array[MatchShapeTemplate] = []
	if u_enabled: templates.append(U)
	if l_enabled: templates.append(L)
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), 118)

static func unlock_run(empty: bool = false) -> RunController:
	var result: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.U_PROFILE)
	result.initialize("fixture_shape_unlock_u_empty" if empty else "fixture_shape_unlock_u")
	return result

static func place(controller: RunController, offsets: Array[Vector2i], origin: Vector2i = Vector2i.ZERO, color: int = 0, missing: Vector2i = Vector2i(-1, -1)) -> void:
	for offset: Vector2i in offsets:
		if offset != missing and controller.state.rules.state.get_piece_at(origin + offset) == null:
			controller.state.rules.place_piece(origin + offset, color)

static func move(controller: RunController, piece: PieceState, target: Vector2i) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(controller.state.run_id, controller.last_command_id + 1, controller.state.action_id)
	command.piece_id = piece.piece_id
	command.target = target
	return controller.execute_command(command)

static func next_coordinate(controller: RunController, target: Vector2i) -> bool:
	var empty: Array[Vector2i] = controller.state.rules.state.get_empty_coordinates()
	for seed_value: int in range(10000):
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		if empty[random.randi_range(0, empty.size() - 1)] == target:
			controller.state.random.seed = seed_value
			return true
	return false
