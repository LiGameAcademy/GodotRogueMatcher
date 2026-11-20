extends GutTest

const PLAYGROUND: PackedScene = preload("res://tools/square_template_playground/square_template_playground.tscn")
const F: Script = preload("res://tests/support/square_template_fixture.gd")
var demo: Node

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	demo = PLAYGROUND.instantiate()
	add_child(demo)
	await demo.fixture_ready
	await wait_process_frames(6)

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	CoreSystem.audio_manager.stop_all()
	demo.queue_free()
	await wait_process_frames(3)

func _choose() -> void:
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	if popup == null: return
	for index: int in range(popup.offer.choices.size()):
		if popup.offer.choices[index].skill_id != &"fixture_unlock_square": continue
		popup._select(index)
		popup.confirm_selection()
		if (demo.get("board") as Board).run.state.ledger.total > 0: await F.confirm_bonus(self)
		return
	fail_test("Square fixture missing from real popup")

func test_playground_starts_at_real_square_choice_and_scores_nine_cells() -> void:
	var board: Board = demo.get("board") as Board
	await _choose()
	assert_true(await wait_until(func() -> bool: return board.can_selected, 6.0))
	assert_eq(board.run.state.ledger.total, 126)
	assert_eq(board.run.state.rules.state.get_piece_count(), 1)
	assert_eq(board.run.state.rules.shape_unlocks.ids(), [&"ring", &"square"])

func test_center_button_retires_waiting_run_and_uses_same_identity() -> void:
	var old_board: Board = demo.get("board") as Board
	var old: RunController = old_board.run
	var button: Button = demo.get_node("Tools/Panel/Rows/Modes/Center") as Button
	button.pressed.emit()
	await demo.fixture_ready
	await wait_process_frames(6)
	assert_true(old.is_retired())
	var board: Board = demo.get("board") as Board
	assert_eq(board.run.initialization, "fixture_shape_unlock_square_center")
	await _choose()
	assert_true(await wait_until(func() -> bool: return board.can_selected, 6.0))
	assert_eq(board.run.state.ledger.total, 0)
	assert_eq(board.run.state.rules.state.get_piece_count(), 10)
	assert_eq(board.run.state.rules.shape_unlocks.ids(), [&"square"])
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(board.run.recorder.records), replay.error)

func test_move_button_installs_replayable_puzzle_and_real_board_input() -> void:
	(demo.get_node("Tools/Panel/Rows/Modes/Move") as Button).pressed.emit()
	await demo.fixture_ready
	var board: Board = demo.get("board") as Board
	assert_true(await wait_until(func() -> bool: return board.can_selected, 6.0))
	board._on_coordinate_pressed(Vector2i(2, 3))
	board._on_coordinate_pressed(Vector2i(2, 2))
	await F.confirm_bonus(self)
	assert_true(await wait_until(func() -> bool: return board.can_selected and board.run.state.valid_moves == 1, 6.0))
	assert_eq(board.run.state.ledger.total, 126)
	assert_eq(board.run.state.rules.state.get_piece_count(), 1)
	assert_eq(board.run.state.spawn_history.size(), 0)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(board.run.recorder.records), replay.error)
func test_real_menu_new_run_stays_in_current_fixture_and_disables_old_shortcuts() -> void:
	var old_board: Board = demo.get("board") as Board
	var old: RunController = old_board.run
	var game: Node2D = demo.get("main").get_node("Game") as Node2D
	(game.get("release_menu") as ReleaseMenu).play_requested.emit(true)
	await demo.fixture_ready
	await wait_process_frames(6)
	var board: Board = demo.get("board") as Board
	assert_true(old.is_retired())
	assert_eq(board.run.initialization, "fixture_shape_unlock_square")
	assert_true(board.run.recorder.path.contains("square_playground_records"))
	game = demo.get("main").get_node("Game") as Node2D
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F6
	game.call("_unhandled_key_input", key)
	await wait_process_frames(3)
	assert_eq(board.run.initialization, "fixture_shape_unlock_square")
	assert_eq(board.run.prototype_profile, RunController.SQUARE_PROFILE)

func test_real_end_popup_retry_restarts_fixture_without_default_record_directory() -> void:
	await _choose()
	var board: Board = demo.get("board") as Board
	assert_true(await wait_until(func() -> bool: return board.can_selected, 6.0))
	var old: RunController = board.run
	GameManager.game_overed.emit()
	assert_true(await wait_until(func() -> bool: return UIManager.current_popup != null and UIManager.current_popup.has_signal("retry_requested"), 6.0))
	if UIManager.current_popup == null: return
	UIManager.current_popup.emit_signal("retry_requested")
	await demo.fixture_ready
	board = demo.get("board") as Board
	assert_true(old.is_retired())
	assert_eq(board.run.initialization, "fixture_shape_unlock_square")
	assert_true(board.run.recorder.path.contains("square_playground_records"))
