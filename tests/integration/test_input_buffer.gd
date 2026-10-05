extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	var main: Node2D = MAIN.instantiate() as Node2D
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	LevelUpSystem.reset_system()
	for x: int in range(4): _place(Vector2i(x, 0), 0)
	board.selected_piece = _place(Vector2i(4, 1), 0)
	_place(Vector2i(8, 8), 1)
	_place(Vector2i(7, 8), 2)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_selection_during_movement_survives_to_next_turn() -> void:
	var next: ChessPiece = board.get_cell(Vector2i(8, 8)).piece
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	board._on_coordinate_pressed(Vector2i(8, 8))
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_same(board.selected_piece, next)
	assert_true(next.is_selected)
	assert_eq(GameManager.turn_count, 2)
	assert_true(board.can_selected)

func test_only_latest_piece_and_one_move_are_buffered() -> void:
	var next: ChessPiece = board.get_cell(Vector2i(7, 8)).piece
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	board._on_coordinate_pressed(Vector2i(8, 8))
	board._on_coordinate_pressed(Vector2i(7, 8))
	board._on_coordinate_pressed(Vector2i(7, 7))
	await GameManager.turn_started
	await wait_process_frames(3)
	assert_eq(board.rules.state.get_piece(next.piece_id).coordinate, Vector2i(7, 7))
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_eq(GameManager.turn_count, 3)
	assert_true(board.can_selected)

func test_removed_buffered_entity_is_not_replaced_by_same_cell_occupant() -> void:
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	board._on_coordinate_pressed(Vector2i(8, 8))
	board.remove_piece(Vector2i(8, 8))
	_place(Vector2i(8, 8), 3)
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_null(board.selected_piece)
	assert_eq(GameManager.turn_count, 2)

func test_retry_discards_buffered_command() -> void:
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	board._on_coordinate_pressed(Vector2i(8, 8))
	board._on_coordinate_pressed(Vector2i(8, 7))
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	await wait_process_frames(3)
	assert_eq(GameManager.turn_count, 1)
	assert_null(board.selected_piece)
	assert_eq(board._buffered_piece_id, 0)

func test_reward_popup_discards_previous_board_intent() -> void:
	GameManager.add_score(50)
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	board._on_coordinate_pressed(Vector2i(8, 8))
	board._on_coordinate_pressed(Vector2i(8, 7))
	await get_tree().create_timer(0.7).timeout
	assert_true(UIManager.current_popup is PopupSkillChoice)
	assert_eq(board._buffered_piece_id, 0)
	(UIManager.current_popup as PopupSkillChoice)._select(0)
	if not board.can_selected: await GameManager.turn_started
	await wait_process_frames(3)
	assert_eq(GameManager.turn_count, 2)
	assert_null(board.selected_piece)

func test_buffered_move_rechecks_target_occupancy() -> void:
	var next: ChessPiece = board.get_cell(Vector2i(8, 8)).piece
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	board._on_coordinate_pressed(Vector2i(8, 8))
	board._on_coordinate_pressed(Vector2i(8, 7))
	_place(Vector2i(8, 7), 3)
	await GameManager.turn_started
	await wait_process_frames(3)
	assert_eq(GameManager.turn_count, 2)
	assert_same(board.selected_piece, next)
	assert_eq(board.rules.state.get_piece(next.piece_id).coordinate, Vector2i(8, 8))

func _place(coordinate: Vector2i, color: int) -> ChessPiece:
	var piece: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	piece.piece_type = color
	board.place_piece(coordinate, piece)
	return piece
