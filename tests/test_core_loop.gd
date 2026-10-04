extends GutTest

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const PIECE_SCENE: PackedScene = preload("res://prefabs/chess_piece.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN_SCENE.instantiate() as Node2D
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	_clear_board()
	LevelUpSystem.reset_system()
	ItemRegistry.register_all_items()

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	ItemEffectSystem.placed_items.clear()
	await wait_process_frames(2)

func test_occupied_start_can_move_and_restores_obstacle() -> void:
	_place(Vector2i(0, 0), 0)
	var result: BoardMoveResult = board.rules.validate_move(board.rules.state.get_piece_id(Vector2i.ZERO), Vector2i(2, 0))
	assert_eq(result.path.size(), 3)
	assert_ne(board.rules.state.get_piece_id(Vector2i.ZERO), 0)
	assert_false(board.rules.validate_move(result.piece_id, Vector2i.ZERO).is_valid())

func test_click_move_advances_one_turn_and_spawns_three() -> void:
	var piece: ChessPiece = _place(Vector2i.ZERO, 0)
	board._on_cell_pressed(board.get_cell(Vector2i.ZERO))
	await board._on_cell_pressed(board.get_cell(Vector2i(2, 0)))
	assert_eq(board.get_cell(Vector2i(2, 0)).piece, piece)
	assert_ne(board.get_cell(Vector2i.ZERO).piece, piece)
	assert_eq(GameManager.turn_count, 2)
	assert_eq(GameManager.piece_count, 4)
	assert_true(board.can_selected)

func test_blocked_move_preserves_turn_score_and_occupancy() -> void:
	var piece: ChessPiece = _place(Vector2i.ZERO, 0)
	_place(Vector2i(1, 0), 1)
	_place(Vector2i(0, 1), 2)
	board.selected_piece = piece
	assert_false(await board.move_selected_piece(board.get_cell(Vector2i(2, 2)), 0.01))
	assert_eq(board.get_cell(Vector2i.ZERO).piece, piece)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(GameManager.score, 0)
	assert_eq(GameManager.piece_count, 3)
	assert_true(board.can_selected)

func test_five_match_scores_and_clears_without_stale_references() -> void:
	for x: int in range(4):
		_place(Vector2i(x, 0), 0)
	var piece: ChessPiece = _place(Vector2i(4, 1), 0)
	_place(Vector2i(8, 8), 1)
	board.selected_piece = piece
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.01))
	await wait_process_frames(2)
	assert_eq(GameManager.score, 50)
	assert_eq(GameManager.piece_count, 1)
	assert_eq(board.get_empty_cells().size(), 80)
	assert_true(board.can_selected)

func test_partial_spawn_fills_last_empty_cell_and_ends_once() -> void:
	_fill_without_lines()
	_remove(Vector2i(8, 8))
	assert_false(GameManager.is_game_over)
	assert_eq(await SpawnManager.spawn_random_pieces(board), 1)
	assert_true(GameManager.is_game_over)
	assert_eq(board.get_empty_cells().size(), 0)
	await wait_process_frames(3)
	assert_true(is_instance_valid(UIManager.current_popup))
	assert_true(UIManager.current_popup.has_signal("retry_requested"))

func test_spawn_checks_match_before_full_board_failure() -> void:
	_fill_without_lines()
	_remove(Vector2i(8, 8))
	# 所有可能出生颜色均有一条经过最后空位的四连。
	for n: int in range(4):
		board.set_piece_color(Vector2i(4 + n, 8), 0)
		board.set_piece_color(Vector2i(8, 4 + n), 1)
		board.set_piece_color(Vector2i(4 + n, 4 + n), 2)
	# 使用确定种子寻找出生颜色0～2，随后恢复同一随机状态。
	seed(17)
	var random_state: int = 0
	for attempt: int in range(100):
		random_state = randi()
		seed(random_state)
		board.get_empty_cells().pick_random()
		if randi_range(0, 4) <= 2:
			break
	seed(random_state)
	assert_eq(await SpawnManager.spawn_random_pieces(board), 3)
	assert_false(GameManager.is_game_over)
	assert_gt(GameManager.score, 0)
	assert_gt(board.get_empty_cells().size(), 0)

func test_crossed_lines_deduplicate() -> void:
	for n: int in range(5):
		_place(Vector2i(n, 2), 0)
		if n != 2:
			_place(Vector2i(2, n), 0)
	assert_eq(MatchSystem.check_for_elimination(board, board.get_cell(Vector2i(2, 2))).size(), 9)

func test_four_does_not_match_and_diagonal_five_does() -> void:
	for n: int in range(4):
		_place(Vector2i(n, n), 2)
	assert_eq(MatchSystem.check_for_elimination(board, board.get_cell(Vector2i(3, 3))).size(), 0)
	_place(Vector2i(4, 4), 2)
	assert_eq(MatchSystem.check_for_elimination(board, board.get_cell(Vector2i(4, 4))).size(), 5)

func test_full_clear_repopulates_and_returns_to_input() -> void:
	for x: int in range(4):
		_place(Vector2i(x, 0), 0)
	board.selected_piece = _place(Vector2i(4, 1), 0)
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.01))
	assert_eq(GameManager.score, 50)
	assert_eq(GameManager.piece_count, 3)
	assert_eq(GameManager.turn_count, 2)
	assert_true(board.can_selected)

func test_failed_spawn_does_not_offer_pending_rescue_reward() -> void:
	_fill_without_lines()
	GameManager.add_score(100)
	assert_eq(await SpawnManager.spawn_random_pieces(board), 0)
	await LevelUpSystem.resolve_pending_rewards(board)
	await wait_process_frames(3)
	assert_true(GameManager.is_game_over)
	assert_false(UIManager.current_popup is PopupLevelUp)
	assert_eq(LevelUpSystem.pending_rewards, 1)

func test_candidate_ids_are_distinct() -> void:
	for attempt: int in range(20):
		var options: Array[ItemData] = LevelUpSystem.generate_options()
		assert_eq(options.size(), 3)
		assert_ne(options[0].id, options[1].id)
		assert_ne(options[0].id, options[2].id)
		assert_ne(options[1].id, options[2].id)

func test_reward_filling_last_space_ends_before_next_reward() -> void:
	_fill_without_lines()
	_remove(Vector2i(8, 8))
	GameManager.add_score(160)
	LevelUpSystem.resolve_pending_rewards(board)
	await wait_process_frames(3)
	var popup: PopupLevelUp = UIManager.current_popup as PopupLevelUp
	popup._on_item_selected(popup.item_options[0])
	await get_tree().create_timer(0.85).timeout
	assert_true(GameManager.is_game_over)
	assert_eq(board.get_empty_cells().size(), 0)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(LevelUpSystem.pending_rewards, 1)
	assert_false(board.can_selected)
	assert_false(UIManager.current_popup is PopupLevelUp)

func test_retry_clears_score_items_obstacles_and_upgrade_state() -> void:
	_fill_without_lines()
	GameManager.score = 123
	LevelUpSystem.pending_rewards = 2
	GameManager.finish_game()
	await wait_process_frames(3)
	UIManager.current_popup.retry_requested.emit()
	await wait_process_frames(5)
	assert_eq(GameManager.score, 0)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(GameManager.piece_count, 3)
	assert_eq(LevelUpSystem.pending_rewards, 0)
	assert_eq(LevelUpSystem.current_level, 0)
	assert_false(GameManager.is_game_over)
	assert_true(board.can_selected)
	assert_eq(ItemEffectSystem.placed_items.size(), 0)
	assert_eq(LevelUpSystem.item_pools["common"].size(), 3)
	for cell: Cell in board.get_empty_cells():
		assert_eq(board.rules.state.get_piece_id(cell.coordinate), 0)

func test_rewards_queue_and_selection_applies_once() -> void:
	GameManager.add_score(160)
	assert_eq(LevelUpSystem.pending_rewards, 2)
	assert_false(is_instance_valid(UIManager.current_popup))
	LevelUpSystem.resolve_pending_rewards(board)
	await wait_process_frames(3)
	var popup: PopupLevelUp = UIManager.current_popup as PopupLevelUp
	assert_not_null(popup)
	var item: ItemData = popup.item_options[0]
	popup._on_item_selected(item)
	popup._on_item_selected(item)
	await get_tree().create_timer(0.85).timeout
	assert_eq(ItemEffectSystem.placed_items.size(), 1)
	var second: PopupLevelUp = UIManager.current_popup as PopupLevelUp
	assert_true(second != popup)
	second._on_item_selected(second.item_options[0])
	await get_tree().create_timer(0.85).timeout
	assert_eq(ItemEffectSystem.placed_items.size(), 2)
	assert_eq(GameManager.piece_count, 2)
	assert_eq(LevelUpSystem.pending_rewards, 0)
	assert_false(LevelUpSystem.is_resolving)
	assert_false(get_tree().paused)

func test_legacy_dye_and_destroy_route_through_rule_state() -> void:
	_place(Vector2i(2, 2), 0)
	var target: ChessPiece = _place(Vector2i(3, 2), 1)
	var dye: EffectDyePiece = EffectDyePiece.new(4, "adjacent", 1)
	assert_true(dye.apply({"board": board, "item_cell": board.get_cell(Vector2i(2, 2))}))
	assert_eq(board.rules.state.get_piece(target.piece_id).match_color, 4)
	assert_eq(target.piece_type, 4)
	var destroy: EffectDestroyPieces = EffectDestroyPieces.new("adjacent", false)
	assert_true(destroy.apply({"board": board, "item_cell": board.get_cell(Vector2i(2, 2))}))
	assert_null(board.rules.state.get_piece(target.piece_id))
	assert_null(board.get_cell(Vector2i(3, 2)).piece)
	assert_eq(GameManager.piece_count, board.rules.state.get_piece_count())
	await get_tree().create_timer(0.3).timeout

func test_game_display_rebuild_does_not_reapply_item_or_reset_rule_ids() -> void:
	var item: ItemData = ItemRegistry.create_prism_tower()
	assert_true(ItemPlacer.place_item_at(board, board.get_cell(Vector2i.ZERO), item))
	var before: PieceState = board.rules.state.get_piece_at(Vector2i.ZERO)
	var previous_display: ChessPiece = board.get_cell(Vector2i.ZERO).piece
	board.rebuild_view()
	assert_eq(board.rules.state.get_piece_at(Vector2i.ZERO).piece_id, before.piece_id)
	assert_ne(board.get_cell(Vector2i.ZERO).piece, previous_display)
	assert_eq(board.get_cell(Vector2i.ZERO).piece.item_data, item)
	assert_eq(ItemEffectSystem.placed_items.size(), 1)
	assert_eq(GameManager.piece_count, 1)

func _clear_board() -> void:
	board.selected_piece = null
	for child: Node in board.view.get_cells():
		if child is Cell:
			_remove((child as Cell).coordinate)
	GameManager.reset_game()
	GameManager.start_turn()
	board.can_selected = true

func _place(coord: Vector2i, color: int) -> ChessPiece:
	var piece: ChessPiece = PIECE_SCENE.instantiate() as ChessPiece
	piece.piece_type = color
	assert_true(board.place_piece(coord, piece))
	return piece

func _remove(coord: Vector2i) -> void:
	board.remove_piece(coord)

func _fill_without_lines() -> void:
	for x: int in range(board.cols):
		for y: int in range(board.rows):
			_place(Vector2i(x, y), (x + 2 * y) % 5)
