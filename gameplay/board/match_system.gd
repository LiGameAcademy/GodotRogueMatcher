extends Node

## 兼容旧信号消费者；计算、移除与计分已移交RunController。
const MIN_MATCH_COUNT: int = 5
signal match_made(score: int, center_pos: Vector2i, matched_cells: Array[Cell])

func check_for_elimination(board: Board, target_cell: Cell) -> Array[Cell]:
	var cells: Array[Cell] = []
	for group: BoardMatchGroup in board.rules.find_matches_at(target_cell.coordinate):
		for piece_id: int in group.piece_ids:
			cells.append(board.get_cell(board.rules.state.get_piece(piece_id).coordinate))
	return cells

func check_and_eliminate(board: Board, target_cell: Cell) -> void:
	board.present_matches(board.run.resolve_matches_at(target_cell.coordinate))

func calculate_score(match_count: int) -> int:
	return ScoreLedger.calculate_base(match_count)