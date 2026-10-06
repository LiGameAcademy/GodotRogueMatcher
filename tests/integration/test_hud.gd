extends GutTest

const HUD: PackedScene = preload("res://ui/hud.tscn")
var hud: Hud

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	hud = HUD.instantiate() as Hud
	add_child_autofree(hud)
	hud.score_duration = 0.12

func after_each() -> void:
	get_tree().paused = false
	await wait_process_frames(2)

func test_score_counts_up_without_mutating_ledger() -> void:
	var before: int = GameManager.score
	hud.show_score(125)
	assert_eq(hud.displayed_score, 0)
	assert_eq(hud.gain_label.text, "+125")
	await wait_process_frames(2)
	assert_lt(hud.displayed_score, 125)
	assert_true(await hud.wait_for_score())
	assert_eq(hud.score_label.text, "分数  125")
	assert_eq(GameManager.score, before)

func test_reset_cancels_old_wait_and_score() -> void:
	var result: Array[bool] = []
	hud.show_score(100)
	var wait: Callable = func() -> void: result.append(await hud.wait_for_score())
	wait.call()
	hud.show_score(0)
	await wait_process_frames(2)
	assert_eq(result, [false])
	assert_eq(hud.displayed_score, 0)
	assert_eq(hud.gain_label.text, "")

func test_pause_freezes_score_but_resume_control_remains_available() -> void:
	hud.show_score(100)
	get_tree().paused = true
	await get_tree().create_timer(0.15).timeout
	assert_eq(hud.displayed_score, 0)
	watch_signals(hud)
	hud.pause_button.pressed.emit()
	assert_signal_emitted(hud, "pause_requested")
	get_tree().paused = false
	assert_true(await hud.wait_for_score())
	assert_eq(hud.displayed_score, 100)

func test_hud_uses_real_reward_occupancy_skill_and_score_data() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91)
	run.state.rewards.acquired[&"instant_thin"] = 2
	run.state.explosion.multiplier_level = 1
	run.state.rewards.acquired[&"score_multiplier"] = 1
	run.state.ledger.commit(5, 1.2, 10, &"match", 1)
	run.state.ledger.commit(0, 1.0, 15, &"explosion", 1)
	hud.show_run(run)
	assert_string_contains(hud.reward_label.text, "还差 15")
	assert_string_contains(hud.board_label.text, "空位 81 / 81")
	assert_string_contains(hud.skills_label.text, "Lv.1")
	assert_string_contains(hud.tools_label.text, "已使用 2 次")
	assert_string_contains(hud.breakdown_label.text, "+85")
	assert_string_contains(hud.breakdown_label.text, "爆炸")
	assert_string_contains(HudDetails.summary(run.state), "85")

func test_prototype_layout_leaves_board_click_area_clear() -> void:
	await wait_process_frames(3)
	assert_lte((hud.get_node("%Left") as Control).get_global_rect().end.x, hud.board_area.get_global_rect().position.x)
	assert_gte((hud.get_node("%Right") as Control).get_global_rect().position.x, hud.board_area.get_global_rect().end.x)
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(hud.skills_label.scroll_active)
	assert_true(hud.breakdown_label.scroll_active)
