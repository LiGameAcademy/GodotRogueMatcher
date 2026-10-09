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

func test_invalid_stage_table_displays_error_without_accessing_missing_target() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, StageConfig.new())
	run.initialize()
	hud.show_run(run)
	assert_eq(run.state.phase, RunState.Phase.ERROR)
	assert_string_contains(hud.reward_label.text, "阶段配置无效")
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.state.next_refill_count(), 0)

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
	assert_eq(hud.goal_progress.current_label.text, "85")
	assert_eq(hud.goal_progress.target_label.text, "100")
	assert_string_contains(hud.board_label.text, "空位 81 / 81")
	assert_string_contains(HudDetails.skills(run.state), "Lv.1")
	assert_string_contains(hud.history_label.text, "已使用 2 次")
	assert_false(hud.history_label.visible)
	assert_string_contains(hud.breakdown_label.text, "+85")
	assert_string_contains(hud.breakdown_label.text, "爆炸")
	assert_string_contains(HudDetails.summary(run.state), "85")

func test_prototype_layout_leaves_board_click_area_clear() -> void:
	await wait_process_frames(3)
	assert_lte((hud.get_node("%Left") as Control).get_global_rect().end.x, hud.board_area.get_global_rect().position.x)
	assert_gte((hud.get_node("%Right") as Control).get_global_rect().position.x, hud.board_area.get_global_rect().end.x)
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.build_list.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_true(hud.breakdown_label.scroll_active)

func test_volume_drag_previews_changes_and_commits_once_on_release() -> void:
	watch_signals(hud)
	hud.volume_slider.drag_started.emit()
	hud.volume_slider.value = 0.25
	hud.volume_slider.value = 0.35
	assert_signal_emit_count(hud, "volume_requested", 2)
	assert_signal_not_emitted(hud, "volume_committed")
	hud.volume_slider.drag_ended.emit(true)
	assert_signal_emit_count(hud, "volume_committed", 1)
	assert_signal_emitted_with_parameters(hud, "volume_committed", [0.35])
	hud.volume_slider.value = 0.55
	assert_signal_emit_count(hud, "volume_committed", 2)
	assert_signal_emitted_with_parameters(hud, "volume_committed", [0.55])

func test_volume_loading_and_unchanged_drag_do_not_request_save() -> void:
	watch_signals(hud)
	hud.set_volume(0.4)
	assert_signal_not_emitted(hud, "volume_requested")
	hud.volume_slider.drag_started.emit()
	hud.volume_slider.drag_ended.emit(false)
	assert_signal_not_emitted(hud, "volume_committed")
	hud.volume_slider.value = 0.6
	assert_signal_emitted_with_parameters(hud, "volume_committed", [0.6])

func test_preview_refresh_and_pause_do_not_consume_or_regenerate_plan() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91)
	run.initialize()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	for index: int in range(5): hud.show_run(run)
	get_tree().paused = true
	hud.show_run(run)
	assert_eq(hud.spawn_preview.title.text, "下次补棋 · 3 枚")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_not_null(hud.build_list)
	assert_true(hud.breakdown_label.bbcode_enabled)
	assert_true(hud.pause_button.get_theme_stylebox("hover") is StyleBoxFlat)

func test_piece_pool_shows_current_conditional_weights_without_mutating_run() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91)
	run.initialize()
	run.state.spawning.color_weights = [4, 4, 6, 4, 4]
	run.state.explosion.core_pool_unlocked = true
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(run))
	hud.show_run(run)
	assert_false(HudDetails.skills(run.state).contains("普通生成权重"))
	assert_false(HudDetails.skills(run.state).contains("核心类型权重"))
	hud.piece_pool.button.mouse_entered.emit()
	assert_true(hud.piece_pool.panel.visible)
	assert_string_contains(hud.piece_pool.details.text, "6/22（27.3%）")
	assert_string_contains(hud.piece_pool.details.text, "爆破手候选")
	hud.piece_pool.button.pressed.emit()
	assert_true(hud.piece_pool._pinned)
	hud.piece_pool.close()
	assert_false(hud.piece_pool.panel.visible)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), baseline)

func test_stage_progress_uses_same_total_including_choice_without_settling() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91, preload("res://gameplay/progression/stages/stage_config.tres"))
	run.initialize()
	run.state.stage.begin_action(1, 0)
	run.state.ledger.commit(5, 1.0, 0, &"match", 1)
	run.state.ledger.commit(0, 1.0, 70, &"match", -1)
	hud.show_run(run)
	assert_eq(hud.goal_progress.current_label.text, "120")
	assert_string_contains(hud.goal_progress.current_label.tooltip_text, "选卡额外得分")
	assert_string_contains(hud.score_label.tooltip_text, "行动 50 + 选卡 70 + 其他 0 = 120")
	assert_string_contains(hud.score_label.tooltip_text, "基础分 × 分数倍率 + 额外得分")
	assert_eq(run.state.ledger.total, 120)
	assert_eq(run.state.stage.action_score, 0)
	assert_eq(run.state.stage.history.size(), 0)

func test_gain_fades_without_delaying_score_barrier_and_reset_cancels_fade() -> void:
	hud.show_score(100)
	assert_true(await hud.wait_for_score())
	assert_eq(hud.gain_label.modulate.a, 1.0)
	await wait_seconds(1.6)
	assert_lt(hud.gain_label.modulate.a, 0.1)
	hud.show_score(200)
	assert_eq(hud.gain_label.modulate.a, 1.0)
	hud.show_score(0)
	assert_eq(hud.gain_label.text, "")

func test_second_stage_shows_cumulative_score_and_target() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91, preload("res://gameplay/progression/stages/stage_config.tres"))
	run.state.ledger.commit(0, 1.0, 120, &"match", 1)
	run.state.stage.index = 1
	hud.show_run(run)
	assert_eq(hud.goal_progress.current_label.text, "120")
	assert_eq(hud.goal_progress.target_label.text, "250")
	assert_eq(hud.goal_progress.bar.min_value, 100.0)
	assert_eq(hud.goal_progress.bar.max_value, 250.0)
	assert_eq(run.state.stage.missing_score(), 130)

func test_pool_escape_closes_it_without_requesting_pause() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91)
	run.initialize()
	hud.show_run(run)
	hud.piece_pool.button.pressed.emit()
	watch_signals(hud)
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_ESCAPE
	get_viewport().push_input(key)
	await wait_process_frames(2)
	assert_false(hud.piece_pool.panel.visible)
	assert_signal_not_emitted(hud, "pause_requested")

func test_top_and_bottom_share_the_same_visible_score_during_flight_and_fill() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 91, preload("res://gameplay/progression/stages/stage_config.tres"))
	hud.show_run(run)
	var entry: ScoreEntry = run.state.ledger.commit(5, 1.0, 0, &"match", 1)
	hud.show_score_burst(entry, Vector2(300, 80))
	hud.show_score(50)
	for frame: int in range(60):
		await wait_process_frames(1)
		assert_eq(hud.displayed_score, roundi(hud.goal_progress.displayed_value))
		if not hud.goal_progress.is_animating(): break
	assert_true(await hud.wait_for_score())
	assert_eq(hud.displayed_score, 50)
	assert_eq(hud.goal_progress.current_label.text, "50")
