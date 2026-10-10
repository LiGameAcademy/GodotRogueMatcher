extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var hud: Hud

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
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func _bind(targets: Array[int]) -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = targets
	for target: int in targets: config.pressure_intervals.append(1)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	run.initialize("fixture_dye")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	board.run = run
	board.rules = run.state.rules
	GameManager.reset_game(run)
	ItemEffectSystem.placed_items.clear()
	board.rebuild_view()
	game.call("_refresh_hud")
	return run

func _move() -> void:
	board.selected_piece = board.get_cell(Vector2i(4, 6)).piece
	board.move_selected_piece(board.get_cell(Vector2i(4, 4)), 0.01)

func _wait_popup() -> void:
	for frame: int in range(360):
		if is_instance_valid(UIManager.current_popup):
			await wait_process_frames(2)
			return
		await wait_process_frames(1)
	fail_test("expected terminal or skill popup")

func test_goal_bonus_keeps_score_label_and_progress_in_sync() -> void:
	var run: RunController = _bind([100, 150])
	run.state.goal_bonus_score = 25
	_move()
	await _wait_popup()
	assert_eq(run.state.ledger.total, 130)
	assert_eq(hud.goal_progress.accepted_value(), 130)
	assert_eq(roundi(hud.goal_progress.displayed_value), 130)
	assert_string_contains(hud.score_label.text, "130")
	assert_string_contains(hud.score_label.tooltip_text, "25")
	assert_string_contains(hud.breakdown_label.text, "25")
	# 完成弹窗生命周期，避免挂起的旧奖励协程影响下一用例。
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	for index: int in range(popup.offer.choices.size()):
		var skill: SkillDefinition = popup.offer.choices[index]
		if skill.choice_effect == null or not skill.choice_effect.requires_color_choice():
			popup._select(index)
			break
	for frame: int in range(360):
		if board.can_selected: break
		await wait_process_frames(1)
	assert_true(board.can_selected)

func test_real_stage_pass_waits_for_presentation_then_enters_next_stage() -> void:
	var run: RunController = _bind([100, 150])
	_move()
	assert_false(is_instance_valid(UIManager.current_popup))
	await _wait_popup()
	assert_true(UIManager.current_popup is PopupSkillChoice)
	assert_false(board.view.is_presenting())
	assert_eq(hud.displayed_score, 105)
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.stage.index, 0)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	for index: int in range(popup.offer.choices.size()):
		var skill: SkillDefinition = popup.offer.choices[index]
		if skill.choice_effect == null or not skill.choice_effect.requires_color_choice():
			popup._select(index)
			break
	for frame: int in range(360):
		if board.can_selected: break
		await wait_process_frames(1)
	assert_true(board.can_selected)
	await wait_process_frames(2)
	assert_eq(run.state.stage.index, 1)
	assert_eq(run.state.stage.carry_in, 5)
	assert_eq(run.state.stage.used_actions, 0)
	assert_eq(run.state.rewards.consumed_count, 1)
	assert_null(UIManager.current_popup)
	assert_string_contains(hud.goal_progress.target_label.tooltip_text, "阶段 2 / 2")
	run.recorder.finish(run, "abandoned", "stage_scene")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)

func test_real_score_shortfall_returns_to_input_after_visuals() -> void:
	var run: RunController = _bind([106])
	_move()
	for frame: int in range(360):
		if board.can_selected: break
		await wait_process_frames(1)
	assert_true(board.can_selected)
	assert_false(run.state.is_game_over)
	assert_eq(run.state.stage.missing_score(), 1)
	assert_false(board.view.is_presenting())
	assert_null(UIManager.current_popup)
	assert_string_contains(hud.spawn_preview.tooltip_text, "下次应补 4 枚")
	run.recorder.finish(run, "abandoned", "stage_scene")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)

func test_real_final_stage_completes_without_skill_popup() -> void:
	var run: RunController = _bind([105])
	_move()
	await _wait_popup()
	assert_eq(run.state.end_reason, &"challenge_completed")
	assert_eq(run.state.pending_rewards, 0)
	assert_eq(run.state.rewards.consumed_count, 0)
	assert_eq((UIManager.current_popup.get_node("Panel/Content/Title") as Label).text, "挑战完成")
	assert_eq(hud.displayed_score, 105)
	assert_false(board.view.is_presenting())
