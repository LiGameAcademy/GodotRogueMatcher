extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const LESSON: PackedScene = preload("res://ui/tutorial/tutorial.tscn")
var game: Node2D
var board: Board

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

func _drain(session: TutorialSession) -> RunStepResult:
	var step: RunStepResult
	for iteration: int in range(16):
		step = session.run.advance()
		if step.kind in [&"input", &"offer", &"error", &"finished"]: return step
	return step
