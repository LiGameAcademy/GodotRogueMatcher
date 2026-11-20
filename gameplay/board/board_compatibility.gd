class_name BoardCompatibility
extends RefCounted

## Legacy scene-editing ports. BoardRules remains the only occupancy mutation authority.
static func place(board: Board, coordinate: Vector2i, piece: ChessPiece) -> bool:
	var content_id: StringName = StringName(piece.item_data.id) if piece.item_data != null else &""
	var snapshot: PieceState = board.rules.place_piece(coordinate, piece.piece_type, content_id, piece.is_ghost)
	if snapshot == null: return false
	board.view.show_piece(snapshot, piece)
	board.refresh_ability_markers()
	board.compatibility_updated()
	return true

static func remove(board: Board, coordinate: Vector2i, animated: bool) -> bool:
	var id: int = board.rules.state.get_piece_id(coordinate)
	var snapshot: PieceState = board.rules.remove_piece(id)
	if snapshot == null: return false
	board.run.state.explosion.instances.erase(id)
	if board.selected_piece == board.view.get_piece(id): board.selected_piece = null
	board.view.remove_piece(snapshot, animated)
	board.compatibility_updated()
	return true

static func color(board: Board, coordinate: Vector2i, match_color: int) -> bool:
	var id: int = board.rules.state.get_piece_id(coordinate)
	if not board.rules.set_piece_color(id, match_color): return false
	board.view.show_color(id, match_color)
	board.refresh_ability_markers()
	board.compatibility_updated()
	return true
