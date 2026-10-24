extends GutTest

const PLAYGROUND: PackedScene = preload("res://tools/mixed_template_playground/mixed_template_playground.tscn")
const F: Script = preload("res://tests/support/mixed_template_fixture.gd")
const DEMO: Script = preload("res://gameplay/skills/debug/mixed_template_demo.gd")
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

func _move() -> Board:
	var board: Board = demo.get("board") as Board
	assert_true(board.can_selected)
	board._on_coordinate_pressed(DEMO.source(board.run.initialization))
	board._on_coordinate_pressed(DEMO.target(board.run.initialization))
	await F.settle_ui(self, board)
	assert_true(board.can_selected)
	assert_eq(board.run.state.rule_error, "")
	assert_eq(board.run.state.valid_moves, 1)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(board.run.recorder.records), replay.error)
	return board

func test_real_board_input_all_four_mixed_cases_and_line_baselines() -> void:
	var totals: Array[int] = [84, 126, 50, 176]
	for index: int in range(4):
		for baseline: bool in [false, true]:
			demo.call("load_fixture", "fixture_mixed_" + DEMO.CASES[index] + ("_baseline" if baseline else ""))
			await demo.fixture_ready
			await wait_process_frames(6)
			var board: Board = await _move()
			assert_eq((demo.get_node("Tools/Panel/Rows/Cases") as OptionButton).selected, index)
			assert_eq((demo.get_node("Tools/Panel/Rows/Baseline") as CheckButton).button_pressed, baseline)
			assert_eq(board.run.state.ledger.total, (50 if index == 3 else 0) if baseline else totals[index])
			assert_eq(board.view._pieces.size(), board.run.state.rules.state.get_piece_count())
			assert_eq(board.run.state.rules.shape_unlocks.recovery_batch_id, 0)

func test_dropdown_baseline_and_reset_retire_old_run_and_keep_same_initial_board() -> void:
	var cases: OptionButton = demo.get_node("Tools/Panel/Rows/Cases") as OptionButton
	cases.select(3)
	cases.item_selected.emit(3)
	await demo.fixture_ready
	await wait_process_frames(6)
	var board: Board = demo.get("board") as Board
	var before: String = RunSnapshot.canonical(board.run.recorder.records[0].initial.pieces)
	var old: RunController = board.run
	var baseline: CheckButton = demo.get_node("Tools/Panel/Rows/Baseline") as CheckButton
	baseline.button_pressed = true
	await demo.fixture_ready
	await wait_process_frames(6)
	board = demo.get("board") as Board
	assert_true(old.is_retired())
	assert_eq(board.run.initialization, "fixture_mixed_nested_baseline")
	assert_eq(RunSnapshot.canonical(board.run.recorder.records[0].initial.pieces), before)
	await _move()
	(demo.get_node("Tools/Panel/Rows/Reset") as Button).pressed.emit()
	await demo.fixture_ready
	await wait_process_frames(6)
	board = demo.get("board") as Board
	assert_eq(board.run.state.valid_moves, 0)
	assert_eq(board.run.initialization, "fixture_mixed_nested_baseline")

func _nested(fast: bool, low: bool) -> void:
	demo.call("load_fixture", "fixture_mixed_nested")
	await demo.fixture_ready
	await wait_process_frames(6)
	var game: Node2D = demo.get("main").get_node("Game") as Node2D
	game.call("_set_fast", fast, false)
	game.call("_set_low_effects", low, false)
	var board: Board = await _move()
	assert_eq(board.run.state.ledger.total, 176)
	assert_eq(board.run.state.rules.state.get_piece_count(), 1)
	assert_eq(board.run.state.rewards.consumed_count, 1)
	assert_eq(board.run.state.spawn_history.size(), 0)
	assert_eq(board.run.state.spawning.refill_batches[-1], 3)

func test_normal_full_mixed_playback_continues_classic_reward() -> void:
	await _nested(false, false)

func test_fast_full_mixed_playback_continues_classic_reward() -> void:
	await _nested(true, false)

func test_low_effects_full_mixed_playback_continues_classic_reward() -> void:
	await _nested(false, true)

func test_fast_low_effects_full_mixed_playback_continues_classic_reward() -> void:
	await _nested(true, true)

func test_menu_and_end_retry_keep_current_mixed_case_and_record_directory() -> void:
	var game: Node2D = demo.get("main").get_node("Game") as Node2D
	var old: RunController = (demo.get("board") as Board).run
	(game.get("release_menu") as ReleaseMenu).play_requested.emit(true)
	await demo.fixture_ready
	await wait_process_frames(6)
	assert_true(old.is_retired())
	var board: Board = await _move()
	assert_eq(board.run.initialization, "fixture_mixed_lt")
	assert_true(board.run.recorder.path.contains("mixed_playground_records"))
	assert_null(board.run.recorder.metadata.screening_result)
	GameManager.game_overed.emit()
	assert_true(await wait_until(func() -> bool: return UIManager.current_popup != null and UIManager.current_popup.has_signal("retry_requested"), 6.0))
	if UIManager.current_popup == null: return
	UIManager.current_popup.emit_signal("retry_requested")
	await demo.fixture_ready
	await wait_process_frames(6)
	board = demo.get("board") as Board
	assert_eq(board.run.initialization, "fixture_mixed_lt")
	assert_eq(board.run.state.valid_moves, 0)
	assert_true(board.run.recorder.path.contains("mixed_playground_records"))

func test_rebuild_disables_controls_and_restores_authoritative_case_after_stale_request() -> void:
	var cases: OptionButton = demo.get_node("Tools/Panel/Rows/Cases") as OptionButton
	var baseline: CheckButton = demo.get_node("Tools/Panel/Rows/Baseline") as CheckButton
	var reset: Button = demo.get_node("Tools/Panel/Rows/Reset") as Button
	demo.call("load_fixture", "fixture_mixed_nested")
	assert_true(demo.get("loading"))
	assert_true(cases.disabled)
	assert_true(baseline.disabled)
	assert_true(reset.disabled)
	# Deliberately inject signals that a disabled native control cannot generate.
	cases.select(0)
	cases.item_selected.emit(0)
	baseline.button_pressed = true
	await demo.fixture_ready
	await wait_process_frames(6)
	assert_false(demo.get("loading"))
	assert_false(cases.disabled)
	assert_false(baseline.disabled)
	assert_false(reset.disabled)
	assert_eq(cases.selected, 3)
	assert_false(baseline.button_pressed)
	assert_eq((demo.get("board") as Board).run.initialization, "fixture_mixed_nested")
