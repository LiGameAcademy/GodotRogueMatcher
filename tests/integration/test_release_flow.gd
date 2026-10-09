extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const LESSON: PackedScene = preload("res://ui/tutorial/tutorial.tscn")
var game: Node2D
var board: Board
var _popup_result: Control
var _popup_finished: bool = false

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	await board.initialized
	await wait_process_frames(2)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_all_four_lessons_use_real_commands_and_isolated_state() -> void:
	var original: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var session: TutorialSession = TutorialSession.new()
	session.reset()
	var config: TutorialConfig = TutorialSession.CONFIG
	var result: CommandResult = session.move(session.run.state.rules.state.get_piece_id(config.source), config.target)
	assert_true(result.accepted)
	assert_eq(session.run.state.ledger.total, 50)
	assert_eq(_drain(session).kind, &"input")
	assert_eq(session.run.state.rules.state.get_piece_count(), 1, "直接五连不补棋")
	session.next_lesson()
	result = session.move(session.run.state.rules.state.get_piece_id(config.spare), config.refill_target)
	assert_true(result.accepted)
	assert_eq(_drain(session).kind, &"input")
	assert_eq(session.run.state.rules.state.get_piece_count(), 4, "普通移动补入3枚")
	session.next_lesson()
	assert_eq(session.run.state.ledger.total, 50)
	result = session.move(session.run.state.rules.state.get_piece_id(config.source), config.target)
	assert_true(result.accepted)
	assert_eq(session.run.state.ledger.total, 100)
	var step: RunStepResult = _drain(session)
	assert_eq(step.kind, &"offer")
	assert_eq(step.offer.choices.size(), 3)
	result = session.choose(step.offer.offer_id, step.offer.choices[0].skill_id)
	assert_true(result.accepted, result.reason)
	assert_eq(_drain(session).kind, &"input")
	assert_eq(session.run.state.rewards.consumed_count, 1)
	session.next_lesson()
	assert_eq(session.run.state.ledger.total, 0, "爆破练习独立初始化")
	assert_true(session.detonate(config.core).accepted)
	assert_eq(_drain(session).kind, &"input")
	assert_eq(session.run.state.activations, 1)
	assert_gt(session.run.state.ledger.total, 0)
	assert_null(session.run.recorder)
	assert_eq(original, RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_help_preserves_board_and_previous_pause_and_replay_can_skip() -> void:
	var original: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	game.call("_show_menu")
	assert_true(get_tree().paused)
	assert_true(menu.visible)
	menu.learn_button.pressed.emit()
	assert_true(menu.tutorial.visible)
	menu.tutorial.skip_button.pressed.emit()
	assert_false(menu.tutorial.visible)
	assert_true(menu.home.visible)
	assert_true(get_tree().paused)
	menu.play_button.pressed.emit()
	assert_false(get_tree().paused)
	assert_eq(original, RunSnapshot.digest(RunSnapshot.capture(board.run)))
	get_tree().paused = true
	game.call("_show_menu")
	menu.play_button.pressed.emit()
	assert_true(get_tree().paused, "原来已暂停，返回后仍保持暂停")

func test_skip_during_animation_cancels_old_completion_and_allows_replay() -> void:
	get_tree().paused = true
	var tutorial: Tutorial = LESSON.instantiate() as Tutorial
	add_child_autofree(tutorial)
	tutorial.start()
	var config: TutorialConfig = TutorialSession.CONFIG
	var result: CommandResult = tutorial.session.move(tutorial.session.run.state.rules.state.get_piece_id(config.source), config.target)
	tutorial._execute(result)
	await wait_process_frames(2)
	tutorial.cancel()
	tutorial.start()
	await wait_process_frames(30)
	assert_eq(tutorial.session.lesson, 0)
	assert_eq(tutorial.session.run.state.ledger.total, 0)
	assert_false(tutorial._completed)
	assert_false(tutorial._busy)
	assert_true(tutorial.next_button.disabled)
	assert_true(get_tree().paused, "练习不自行释放正式局暂停")

func test_tutorial_choice_occurs_after_animation_while_tree_paused() -> void:
	var tutorial: Tutorial = LESSON.instantiate() as Tutorial
	add_child_autofree(tutorial)
	tutorial.start()
	var session: TutorialSession = tutorial.session
	var config: TutorialConfig = TutorialSession.CONFIG
	session.move(session.run.state.rules.state.get_piece_id(config.source), config.target)
	_drain(session)
	session.next_lesson()
	session.move(session.run.state.rules.state.get_piece_id(config.spare), config.refill_target)
	_drain(session)
	session.next_lesson()
	tutorial._show_lesson()
	get_tree().paused = true
	var result: CommandResult = session.move(session.run.state.rules.state.get_piece_id(config.source), config.target)
	tutorial._execute(result)
	assert_false(tutorial.choices.visible)
	for frame: int in range(180):
		if tutorial.choices.visible: break
		await wait_process_frames(1)
	assert_true(tutorial.choices.visible)
	assert_false(tutorial.view.is_presenting())
	assert_eq(tutorial.score.text, "练习得分 100 · 空位 24 / 25")
	tutorial.choices._select(0)
	for frame: int in range(180):
		if tutorial._completed: break
		await wait_process_frames(1)
	assert_true(tutorial._completed)
	assert_false(tutorial.choices.visible)
	assert_true(get_tree().paused)

func test_build_label_uses_application_version_and_explicit_override() -> void:
	var recorder: RunRecorder = RunRecorder.new()
	recorder.begin(board.run, "test", false)
	assert_eq(recorder.records[0].build, "0.0.1")
	var explicit: RunRecorder = RunRecorder.new()
	explicit.begin(board.run, "test", false, "fixture-build")
	assert_eq(explicit.records[0].build, "fixture-build")

func test_switching_modes_starts_new_runs_and_preserves_mode_on_retry() -> void:
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	var original: RunController = board.run
	assert_eq(original.state.mode_id(), &"stage_challenge")
	game.call("_show_menu")
	menu.mode_button.select(0)
	menu.mode_button.item_selected.emit(0)
	assert_string_contains(menu.mode_hint.text, "重置")
	menu.play_button.pressed.emit()
	await board.initialized
	assert_ne(board.run.state.run_id, original.state.run_id)
	assert_eq(board.run.state.mode_id(), &"classic_endless")
	assert_eq(board.run.state.valid_moves, 0)
	assert_eq(board.run.state.rewards.consumed_count, 0)
	assert_false(get_tree().paused)
	game.call("_show_menu")
	assert_eq(menu.mode_button.selected, 0)
	menu.mode_button.select(1)
	menu.play_button.pressed.emit()
	await board.initialized
	assert_eq(board.run.state.mode_id(), &"stage_challenge")
	assert_eq(board.run.state.stage.used_actions, 0)
	assert_eq(board.run.state.stage.index, 0)
	var previous_id: String = board.run.state.run_id
	game.call("_show_menu")
	menu.new_button.pressed.emit()
	await board.initialized
	assert_ne(board.run.state.run_id, previous_id)
	assert_eq(board.run.state.mode_id(), &"stage_challenge")

func test_challenge_hud_and_end_titles_use_stage_state() -> void:
	var hud: Hud = game.get_node("UILayer/HUD") as Hud
	assert_string_contains(hud.reward_label.text, "阶段 1 / 8")
	assert_string_contains(hud.reward_label.text, "剩余行动 10 / 10")
	board.run.state.stage.carry_in = 100
	hud.show_run(board.run)
	assert_string_contains(hud.reward_label.text, "完成一次有效行动")
	board.run.state.stage.used_actions = 10
	board.run.finish_game(&"stage_target_missed")
	var popup: Control = await UIManager.open_popup("popup_game_over", {"score": 0, "run_state": board.run.state})
	assert_eq((popup.get_node("Panel/Content/Title") as Label).text, "行动耗尽 · 阶段挑战失败")
	assert_string_contains(HudDetails.summary(board.run.state), "已用行动 10 / 10")
	UIManager.close_popup()
	board.run.state.end_reason = &"challenge_completed"
	assert_eq(StageText.end_title(board.run.state), "挑战完成")

func test_closing_popup_during_initialization_does_not_resume_stale_dialog() -> void:
	_popup_finished = false
	_open_popup()
	UIManager.close_popup()
	await wait_process_frames(3)
	assert_true(_popup_finished)
	assert_null(_popup_result)
	assert_null(UIManager.current_popup)
	assert_false(get_tree().paused)

func _open_popup() -> void:
	_popup_result = await UIManager.open_popup("popup_game_over", {"score": 50})
	_popup_finished = true

func _drain(session: TutorialSession) -> RunStepResult:
	var step: RunStepResult
	for iteration: int in range(16):
		step = session.run.advance()
		if step.kind in [&"input", &"offer", &"error", &"finished"]: return step
	return step
