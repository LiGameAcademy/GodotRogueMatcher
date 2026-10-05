extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	ItemEffectSystem.placed_items.clear()
	await wait_process_frames(2)

func test_f6_demo_loads_markers_and_real_move_resolves_two_generations() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F6
	key.pressed = true
	main.get_node("Game").call("_unhandled_key_input", key)
	assert_eq(board.rules.state.get_piece_count(), 9)
	assert_eq(board.get_cell(Vector2i(5, 5)).piece.ability_marker.text, "爆")
	assert_eq(board.get_cell(Vector2i(6, 4)).piece.ability_marker.text, "引")
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01))
	assert_eq(GameManager.score, 70)
	assert_eq(board.rules.state.get_piece_count(), 3)
	assert_eq(GameManager.ledger.get_entries().size(), 3)
	assert_eq(GameManager.turn_count, 2)
	assert_true(board.can_selected)
	assert_eq(board.run.state.explosion.instances.size(), 0)

func test_two_playback_speeds_keep_chain_scores_and_targets_identical() -> void:
	for duration: float in [0.01, 0.1]:
		assert_true(board.load_explosion_demo())
		board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
		assert_true(await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), duration))
		assert_eq(GameManager.score, 70)
		var entries: Array[ScoreEntry] = GameManager.ledger.get_entries()
		assert_eq(entries[1].target_ids.size(), 2)
		assert_eq(entries[2].target_ids.size(), 2)
		assert_eq(board.rules.state.get_piece_count(), 3)

func test_retry_while_explosion_move_is_playing_drops_old_abilities() -> void:
	board.load_explosion_demo()
	var old_run: RunController = board.run
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.4)
	assert_eq(old_run.state.ledger.total, 70)
	main.get_node("Game").call("_on_retry_requested")
	await board.initialized
	assert_ne(board.run, old_run)
	assert_eq(GameManager.score, 0)
	assert_eq(board.run.state.explosion.instances.size(), 0)
	assert_eq(board.run.state.explosion.reward_level, 0)
	assert_false(board.run.state.explosion.unlocked)
	assert_eq(GameManager.turn_count, 1)
	assert_true(board.can_selected)

func test_birth_fault_stops_scene_input_without_full_board_game_over() -> void:
	board.selected_piece = null
	for piece: PieceState in board.rules.state.get_snapshot():
		board.remove_piece(piece.coordinate)
	for x: int in range(9):
		for y: int in range(9):
			if Vector2i(x, y) != Vector2i(8, 8):
				board.rules.place_piece(Vector2i(x, y), (x + 2 * y) % 5)
	for x: int in range(4, 8):
		board.rules.set_piece_color(board.rules.state.get_piece_id(Vector2i(x, 8)), 0)
	board.view.rebuild(board.rules.state.get_snapshot())
	for run_seed: int in range(1000):
		board.run.state.random.seed = run_seed
		board.run.state.random.randi_range(0, 0)
		if board.run.state.random.randi_range(0, 4) == 0:
			board.run.state.random.seed = run_seed
			break
	var config: ExplosionConfig = board.run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 0
	board.run.abilities.config = config
	assert_eq(await SpawnManager.spawn_random_pieces(board), 1)
	assert_eq(board.run.state.phase, RunState.Phase.ERROR)
	assert_false(board.can_selected)
	assert_false(GameManager.is_game_over)
	assert_false(is_instance_valid(UIManager.current_popup))
