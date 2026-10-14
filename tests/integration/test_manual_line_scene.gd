extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	var main: Node2D = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	# Sound cues are asserted at the board boundary; avoid audio backend tails at CLI exit.
	(main.get_node("Game/GameFeedback") as GameFeedback).set_volume(0.0)
	assert_true(board.load_explosion_demo("fixture_line"))

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_f11_debug_entry_loads_replayable_fixture_and_shows_unlocked_tooltip() -> void:
	var game: Node = board.get_parent()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F11
	key.pressed = true
	await game._unhandled_key_input(key)
	assert_eq(board.run.initialization, "fixture_line")
	assert_eq(board.run.state.line_clear.level(&"line_manual_clear"), 1)
	game._on_locale_changed("zh_CN", "en_US")
	var source_id: int = board.rules.state.get_piece_id(Vector2i.ZERO)
	assert_string_contains(board.view.get_piece(source_id).tooltip_region.tooltip_text, String(TranslationServer.translate("双击主动扫线：消耗本枚和一次行动，正常补棋。")))

func test_double_click_fast_and_normal_scene_match_headless_rules_and_replay() -> void:
	for fast: bool in [false, true]:
		assert_true(board.load_explosion_demo("fixture_line"))
		board.set_playback_fast(fast)
		var run: RunController = board.run
		watch_signals(board)
		var shadow: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
		shadow.state.run_id = run.state.run_id
		shadow.initialize("fixture_line")
		var source: PieceState = shadow.state.rules.state.get_piece(shadow.state.rules.state.get_piece_id(Vector2i.ZERO))
		var command: ActivateLineCommand = ActivateLineCommand.new(shadow.state.run_id, 1, shadow.state.action_id)
		command.piece_id = source.piece_id
		assert_true(shadow.execute_command(command).accepted)
		while shadow.state.phase != RunState.Phase.INPUT and not shadow.state.is_game_over: shadow.advance()
		await board._on_piece_activated(Vector2i.ZERO)
		assert_signal_emitted_with_parameters(board, "feedback_requested", [&"blast"])
		assert_true(board.can_selected)
		assert_eq(run.state.activations, 1)
		assert_eq(run.state.ledger.total, 14)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), RunSnapshot.digest(RunSnapshot.capture(shadow)))
		assert_true(board.view.align_snapshot(run.state.rules.state.get_snapshot()))
		run.recorder.finish(run, "abandoned", "manual_line_scene")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(run.recorder.path), replay.error)
