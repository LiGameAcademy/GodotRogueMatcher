extends RefCounted

## Builds read-only interaction feedback from authoritative rules; owns no run state.

static func selection_paths(rules: BoardRules, piece_id: int) -> Dictionary[Vector2i, BoardMoveResult]:
	var paths: Dictionary[Vector2i, BoardMoveResult] = {}
	if rules == null or piece_id == 0: return paths
	for coordinate: Vector2i in rules.state.get_empty_coordinates():
		var result: BoardMoveResult = rules.validate_move(piece_id, coordinate)
		if result.is_valid(): paths[coordinate] = result
	return paths

static func activation_command(run: RunController, coordinate: Vector2i) -> RunCommand:
	var piece: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(coordinate))
	if piece == null: return null
	if LineClearState.is_line_piece(piece.content_id):
		var activate: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
		activate.piece_id = piece.piece_id
		return activate
	var detonate: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	detonate.piece_id = piece.piece_id
	return detonate

## An accepted manual blast or sweep with no targets still consumes its normal action.
static func is_empty_activation(turn: TurnResult) -> bool:
	if turn.move != null or turn.matches.is_empty(): return false
	for result: MatchResult in turn.matches:
		if result.cause not in [&"explosion", &"line_clear"] or not result.removed.is_empty(): return false
	return true
