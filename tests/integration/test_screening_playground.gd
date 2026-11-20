extends GutTest

const PLAYGROUND: PackedScene = preload("res://tools/screening_playground/screening_playground.tscn")
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

func _open(key: String, task: String) -> Board:
	demo.call("load_fixture", key, task)
	await demo.fixture_ready
	await wait_process_frames(6)
	return demo.get("board") as Board

func _complete_fixed(board: Board) -> void:
	board._on_coordinate_pressed(ScreeningDeck.source(board.run.initialization))
	board._on_coordinate_pressed(ScreeningDeck.target(board.run.initialization))
	var ready: bool = await wait_until(func() -> bool:
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		return bool(demo.get("stopped")) or (is_instance_valid(popup) and popup.offer != null), 6.0)
	assert_true(ready)
	if not ready: return
	if not bool(demo.get("stopped")):
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		assert_eq(popup.offer.choices[0].skill_id, &"fixture_screening_refill")
		popup._select(0)
		popup.confirm_selection()
	assert_true(await wait_until(func() -> bool: return bool(demo.get("stopped")), 6.0))
	assert_false(board.can_selected)
	assert_true(board.run.is_retired())
	assert_eq(board.run.state.valid_moves, 1)
	assert_eq(demo.get("stop_reason"), "fixed_complete")
	assert_eq(board.run.state.rule_error, "")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)
	var file: FileAccess = FileAccess.open(str(demo.get("summary_path")), FileAccess.READ)
	assert_not_null(file)
	var data: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	assert_null(data.participant)
	assert_null(data.predictions)
	assert_null(data.selection_decision)
	assert_eq(data.actions, 1)
	assert_eq(board.view._pieces.size(), board.run.state.rules.state.get_piece_count())

func test_all_twenty_four_fixed_tasks_run_real_scene_and_seal_one_complete_action() -> void:
	for key: String in ScreeningDeck.CONFIGS:
		for task: String in ScreeningDeck.TASKS.slice(1):
			var board: Board = await _open(key, task)
			await _complete_fixed(board)
			assert_eq((demo.get_node("Tools/Panel/Rows/Configurations") as OptionButton).selected, ScreeningDeck.CONFIGS.find(key))
			assert_eq((demo.get_node("Tools/Panel/Rows/Tasks") as OptionButton).selected, ScreeningDeck.TASKS.find(task))

func _overlap(fast: bool, low: bool) -> void:
	var board: Board = await _open("t", "overlap")
	var game: Node2D = demo.get("main").get_node("Game") as Node2D
	game.call("_set_fast", fast, false)
	game.call("_set_low_effects", low, false)
	await _complete_fixed(board)
	assert_eq(board.run.state.ledger.total, 126)
	assert_eq(board.run.state.rewards.consumed_count, 1)
	assert_eq(board.run.state.spawn_history.size(), 0)
	assert_eq(board.run.state.rules.state.get_piece_count(), 1)

func test_normal_fixed_bonus_finishes_before_sealing() -> void:
	await _overlap(false, false)

func test_fast_fixed_bonus_finishes_before_sealing() -> void:
	await _overlap(true, false)

func test_low_effects_fixed_bonus_finishes_before_sealing() -> void:
	await _overlap(false, true)

func test_fast_low_fixed_bonus_finishes_before_sealing() -> void:
	await _overlap(true, true)

func _start_free_move(board: Board) -> void:
	for piece: PieceState in board.run.state.rules.state.get_snapshot():
		for direction: Vector2i in BoardRules.MOVE_DIRECTIONS:
			var target: Vector2i = piece.coordinate + direction
			if board.rules.state.is_valid_coordinate(target) and board.rules.state.get_piece_at(target) == null:
				board._on_coordinate_pressed(piece.coordinate)
				board._on_coordinate_pressed(target)
				return
	fail_test("opening must have a legal adjacent move")

func test_action_budget_seals_after_real_move_and_blocks_stale_or_buffered_action() -> void:
	var board: Board = await _open("l", "free")
	var settings: ScreeningConfig = (demo.get("settings") as ScreeningConfig).duplicate(true) as ScreeningConfig
	settings.action_limit = 1
	demo.set("settings", settings)
	_start_free_move(board)
	assert_true(await wait_until(func() -> bool: return bool(demo.get("stopped")), 6.0))
	assert_eq(demo.get("stop_reason"), "action_limit")
	assert_eq(board.run.state.valid_moves, 1)
	assert_eq(board.run.state.spawn_history.size(), RunController.CONFIG.initial_piece_count + 3)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(board.run))
	board.can_selected = true # Deliberately stale outer UI state must not admit a second command.
	var command: MovePieceCommand = MovePieceCommand.new(board.run.state.run_id, board.run.last_command_id + 1, board.run.state.action_id)
	assert_false(await board._execute_action(command, 0.0))
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(board.run)), before)
	assert_eq(ScreeningDeck.config("l").action_limit, 15)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)

func test_time_budget_does_not_cut_playback_and_pause_is_included() -> void:
	var board: Board = await _open("baseline", "free")
	_start_free_move(board)
	var settings: ScreeningConfig = (demo.get("settings") as ScreeningConfig).duplicate(true) as ScreeningConfig
	settings.time_limit_seconds = 0
	demo.set("settings", settings)
	assert_false(demo.get("stopped"))
	assert_true(await wait_until(func() -> bool: return bool(demo.get("stopped")), 6.0))
	assert_eq(demo.get("stop_reason"), "time_limit")
	assert_eq(board.run.state.valid_moves, 1)
	assert_eq(board.run.state.spawn_history.size(), RunController.CONFIG.initial_piece_count + 3)
	var elapsed: int = int(demo.call("elapsed_ms"))
	await wait_process_frames(3)
	assert_eq(int(demo.call("elapsed_ms")), elapsed)
	board = await _open("baseline", "free")
	demo.set("settings", settings)
	get_tree().paused = true
	await wait_process_frames(3)
	assert_true(demo.get("stopped"))
	assert_eq(demo.get("stop_reason"), "time_limit")
	assert_eq(board.run.state.valid_moves, 0)

func test_controls_and_menu_restart_keep_configuration_and_close_old_record() -> void:
	var board: Board = await _open("x", "outside")
	var old: RunController = board.run
	var game: Node2D = demo.get("main").get_node("Game") as Node2D
	(game.get("release_menu") as ReleaseMenu).play_requested.emit(true)
	assert_true((demo.get_node("Tools/Panel/Rows/Configurations") as OptionButton).disabled)
	assert_true((demo.get_node("Tools/Panel/Rows/Tasks") as OptionButton).disabled)
	await demo.fixture_ready
	await wait_process_frames(6)
	assert_true(old.is_retired())
	assert_true(old.recorder.ended)
	board = demo.get("board") as Board
	assert_eq(board.run.initialization, "screening_x_outside")
	assert_eq((demo.get_node("Tools/Panel/Rows/Configurations") as OptionButton).selected, 4)
	assert_eq((demo.get_node("Tools/Panel/Rows/Tasks") as OptionButton).selected, 4)
	await _complete_fixed(board)

func test_switching_while_reward_waits_closes_old_sample_and_does_not_touch_new_free_run() -> void:
	var board: Board = await _open("t", "overlap")
	board._on_coordinate_pressed(ScreeningDeck.source(board.run.initialization))
	board._on_coordinate_pressed(ScreeningDeck.target(board.run.initialization))
	assert_true(await wait_until(func() -> bool:
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		return is_instance_valid(popup) and popup.offer != null, 6.0))
	var old: RunController = board.run
	board = await _open("zs", "free")
	assert_true(old.is_retired())
	assert_true(old.recorder.ended)
	assert_eq(old.recorder.records.back().status, "abandoned")
	assert_eq(board.run.state.valid_moves, 0)
	assert_eq(board.run.state.ledger.total, 0)
	assert_eq(board.run.prototype_profile, RunController.SCREENING_PROFILE)
	assert_true(board.can_selected)
	assert_null(UIManager.current_popup)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(old.recorder.path), replay.error)

func test_closing_during_initialization_does_not_try_to_seal_temporary_unrecorded_run() -> void:
	var pending: Node = PLAYGROUND.instantiate()
	add_child(pending)
	assert_true(pending.get("loading"))
	assert_null(pending.get("session"))
	var temporary: Board = pending.get("board") as Board
	assert_not_null(temporary)
	assert_null(temporary.run.recorder)
	pending.queue_free()
	await wait_process_frames(5)
	assert_false(is_instance_valid(pending))
	# Also cover teardown during a second initialization after an owned sample existed.
	var old: RunController = (demo.get("board") as Board).run
	demo.call("load_fixture", "l", "direct")
	assert_true(old.recorder.ended)
	assert_null(demo.get("session"))
	demo.call("_finish", "closed")
	await demo.fixture_ready
	await wait_process_frames(6)
	assert_false(demo.get("stopped"))
	assert_not_null(demo.get("session"))
