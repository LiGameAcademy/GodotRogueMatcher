extends GutTest

const GOAL: PackedScene = preload("res://ui/goal_progress/goal_progress.tscn")
var goal: GoalProgress

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	goal = GOAL.instantiate() as GoalProgress
	goal.position = Vector2(20, 350)
	goal.size = Vector2(600, 24)
	add_child_autofree(goal)
	goal.show_goal("test", 0, 0, 100, "当前分数", "目标分数", "规则")
	await wait_process_frames(2)

func after_each() -> void:
	get_tree().paused = false
	await wait_process_frames(2)

func test_light_starts_at_source_and_fill_waits_for_arrival() -> void:
	var source: Vector2 = Vector2(320, 80)
	goal.add_gain(50, source)
	var mote: ScoreMote = goal.motes.get_child(0) as ScoreMote
	assert_almost_eq(mote.get_global_transform_with_canvas().origin.x, source.x, 0.1)
	assert_almost_eq(mote.get_global_transform_with_canvas().origin.y, source.y, 0.1)
	assert_eq(goal.bar.value, 0.0)
	await wait_seconds(0.12)
	assert_eq(goal.bar.value, 0.0)
	assert_ne(mote.global_position, source)
	assert_true(await goal.wait_until_settled())
	assert_almost_eq(goal.bar.value, 50.0, 0.01)
	assert_eq(goal.current_label.text, "50")
	assert_eq(goal.motes.get_child_count(), 0)

func test_many_gains_merge_at_limit_and_skip_preserves_exact_total() -> void:
	for index: int in range(24): goal.add_gain(5, Vector2(300, 80))
	assert_eq(goal.motes.get_child_count(), goal.config.maximum_motes)
	assert_true(goal.finish_now())
	assert_eq(goal.current_label.text, "120")
	assert_eq(goal.bar.value, 100.0)
	assert_false(goal.is_animating())
	await wait_seconds(0.8)
	assert_eq(goal.current_label.text, "120")

func test_pause_freezes_flight_and_reset_cancels_old_wait() -> void:
	goal.add_gain(50, Vector2(300, 80))
	get_tree().paused = true
	await get_tree().create_timer(0.45).timeout
	assert_eq(goal.bar.value, 0.0)
	assert_eq(goal.motes.get_child_count(), 1)
	get_tree().paused = false
	var waited: Array[bool] = []
	var wait: Callable = func() -> void: waited.append(await goal.wait_until_settled())
	wait.call()
	goal.show_goal("next-run", 20, 0, 150, "", "", "")
	await wait_process_frames(2)
	assert_eq(waited, [false])
	assert_eq(goal.current_label.text, "20")
	await wait_seconds(0.8)
	assert_eq(goal.current_label.text, "20")

func test_low_effects_and_materials_are_isolated_between_instances() -> void:
	var other: GoalProgress = GOAL.instantiate() as GoalProgress
	add_child_autofree(other)
	other.show_goal("other", 0, 0, 100, "", "", "")
	assert_not_same(goal.glow.material, other.glow.material)
	goal._pulse()
	assert_eq((other.glow.material as ShaderMaterial).get_shader_parameter("intensity"), 0.0)
	goal.set_low_effects(true)
	goal.add_gain(25, Vector2(300, 80))
	assert_eq(goal.motes.get_child_count(), 0)
	assert_true(await goal.wait_until_settled())
	assert_eq(goal.current_label.text, "25")
	assert_eq((goal.glow.material as ShaderMaterial).get_shader_parameter("intensity"), 0.0)

func test_all_score_waiters_finish_when_first_waiter_advances_goal() -> void:
	goal.add_gain(100, Vector2(300, 80))
	var results: Array[bool] = []
	var advance: Callable = func() -> void:
		results.append(await goal.wait_until_settled())
		goal.show_goal("next-goal", 100, 100, 250, "", "", "")
	var other: Callable = func() -> void: results.append(await goal.wait_until_settled())
	advance.call()
	other.call()
	await wait_seconds(0.8)
	assert_eq(results, [true, true])
	assert_eq(goal.target_label.text, "250")
