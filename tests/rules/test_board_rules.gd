extends GutTest

var state: BoardState
var rules: BoardRules

func before_each() -> void:
	state = BoardState.new(9, 9)
	rules = BoardRules.new(state, 5)

func test_invalid_moves_do_not_mutate_state_or_random_stream() -> void:
	var source: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	var occupied: PieceState = rules.place_piece(Vector2i(2, 0), 1)
	seed(314)
	var expected_random: int = randi()
	seed(314)
	assert_eq(rules.move_piece(0, Vector2i(1, 0)).failure, BoardMoveResult.Failure.INVALID_PIECE)
	assert_eq(rules.move_piece(source.piece_id, Vector2i(-1, 0)).failure, BoardMoveResult.Failure.OUT_OF_BOUNDS)
	assert_eq(rules.move_piece(source.piece_id, Vector2i(9, 0)).failure, BoardMoveResult.Failure.OUT_OF_BOUNDS)
	assert_eq(rules.move_piece(source.piece_id, Vector2i.ZERO).failure, BoardMoveResult.Failure.SAME_CELL)
	assert_eq(rules.move_piece(source.piece_id, occupied.coordinate).failure, BoardMoveResult.Failure.TARGET_OCCUPIED)
	assert_eq(state.get_piece_count(), 2)
	assert_eq(state.get_piece(source.piece_id).coordinate, Vector2i.ZERO)
	assert_eq(state.get_piece(occupied.piece_id).coordinate, Vector2i(2, 0))
	assert_eq(randi(), expected_random)

func test_four_neighbor_path_never_moves_diagonally() -> void:
	var source: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	var result: BoardMoveResult = rules.move_piece(source.piece_id, Vector2i(2, 2))
	assert_true(result.is_valid())
	assert_eq(result.path.size(), 5)
	for index: int in range(1, result.path.size()):
		var delta: Vector2i = result.path[index] - result.path[index - 1]
		assert_eq(absi(delta.x) + absi(delta.y), 1)
	assert_eq(state.get_piece_id(Vector2i.ZERO), 0)
	assert_eq(state.get_piece_id(Vector2i(2, 2)), source.piece_id)

func test_blocked_corner_rejects_diagonal_escape() -> void:
	var source: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	rules.place_piece(Vector2i.RIGHT, 1)
	rules.place_piece(Vector2i.DOWN, 1)
	assert_eq(rules.move_piece(source.piece_id, Vector2i(1, 1)).failure, BoardMoveResult.Failure.NO_PATH)
	assert_eq(state.get_piece(source.piece_id).coordinate, Vector2i.ZERO)

func test_path_detours_around_occupied_cell() -> void:
	var source: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	rules.place_piece(Vector2i(1, 0), 1)
	var result: BoardMoveResult = rules.validate_move(source.piece_id, Vector2i(2, 0))
	assert_true(result.is_valid())
	assert_eq(result.path.size(), 5)
	assert_false(result.path.has(Vector2i(1, 0)))
	assert_eq(state.get_piece(source.piece_id).coordinate, Vector2i.ZERO)

func test_rectangular_board_uses_columns_for_x_and_rows_for_y() -> void:
	state = BoardState.new(6, 3)
	rules = BoardRules.new(state, 5)
	var source: PieceState = rules.place_piece(Vector2i(5, 2), 0)
	assert_not_null(source)
	assert_null(rules.place_piece(Vector2i(2, 3), 0))
	assert_null(rules.place_piece(Vector2i(6, 2), 0))
	assert_true(rules.move_piece(source.piece_id, Vector2i.ZERO).is_valid())
	assert_eq(state.get_empty_coordinates().size(), 17)

func test_four_is_not_a_match_and_long_lines_are_complete() -> void:
	for x: int in range(4):
		rules.place_piece(Vector2i(x, 0), 0)
	assert_eq(rules.find_matches().size(), 0)
	for x: int in range(4, 8):
		rules.place_piece(Vector2i(x, 0), 0)
	var groups: Array[BoardMatchGroup] = rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 8)
	assert_eq(rules.find_matches_at(Vector2i(8, 0)).size(), 0)

func test_both_diagonal_directions_match() -> void:
	for index: int in range(5):
		rules.place_piece(Vector2i(index, index), 0)
		rules.place_piece(Vector2i(index + 4, 8 - index), 1)
	var groups: Array[BoardMatchGroup] = rules.find_matches()
	assert_eq(groups.size(), 2)
	for group: BoardMatchGroup in groups:
		assert_eq(group.piece_ids.size(), 5)

func test_t15_independent_lines_remain_two_groups() -> void:
	for x: int in range(5):
		rules.place_piece(Vector2i(x, 0), 0)
		rules.place_piece(Vector2i(x, 3), 0)
	var groups: Array[BoardMatchGroup] = rules.find_matches()
	assert_eq(groups.size(), 2)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(groups[1].piece_ids.size(), 5)
	for piece_id: int in groups[0].piece_ids:
		assert_false(groups[1].piece_ids.has(piece_id))

func test_t16_crossed_lines_merge_nine_unique_ids() -> void:
	for index: int in range(5):
		rules.place_piece(Vector2i(index, 2), 0)
		if index != 2:
			rules.place_piece(Vector2i(2, index), 0)
	var groups: Array[BoardMatchGroup] = rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 9)
	assert_eq(rules.find_matches_at(Vector2i(2, 2)).size(), 1)
	var unique_ids: Dictionary[int, bool] = {}
	for piece_id: int in groups[0].piece_ids:
		assert_false(unique_ids.has(piece_id))
		unique_ids[piece_id] = true

func test_bridge_line_merges_multiple_existing_groups() -> void:
	for y: int in [0, 4]:
		for x: int in range(5):
			rules.place_piece(Vector2i(x, y), 0)
	for y: int in range(1, 4):
		rules.place_piece(Vector2i(2, y), 0)
	var groups: Array[BoardMatchGroup] = rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 13)

func test_failed_placement_does_not_consume_entity_id() -> void:
	var first: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	assert_null(rules.place_piece(Vector2i.ZERO, 1))
	assert_null(rules.place_piece(Vector2i(-1, 0), 1))
	assert_null(rules.place_piece(Vector2i(1, 0), -1))
	var second: PieceState = rules.place_piece(Vector2i(1, 0), 1)
	assert_eq(second.piece_id, first.piece_id + 1)

func test_snapshots_and_two_boards_are_isolated() -> void:
	var first: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	var other_state: BoardState = BoardState.new(9, 9)
	var other_rules: BoardRules = BoardRules.new(other_state, 5)
	other_rules.place_piece(Vector2i.ZERO, 0)
	first.coordinate = Vector2i(8, 8)
	var snapshot: Array[PieceState] = state.get_snapshot()
	snapshot[0].match_color = 4
	snapshot.clear()
	assert_eq(state.get_piece(first.piece_id).coordinate, Vector2i.ZERO)
	assert_eq(state.get_piece(first.piece_id).match_color, 0)
	assert_true(rules.set_piece_color(first.piece_id, 2))
	assert_eq(other_state.get_piece(first.piece_id).match_color, 0)
	assert_not_null(rules.remove_piece(first.piece_id))
	assert_null(rules.remove_piece(first.piece_id))
	assert_false(rules.set_piece_color(first.piece_id, 3))
	assert_eq(state.get_empty_coordinates().size(), 81)
	assert_eq(other_state.get_piece_count(), 1)
