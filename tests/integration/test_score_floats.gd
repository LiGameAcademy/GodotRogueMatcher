extends GutTest

const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
const FLOAT: PackedScene = preload("res://gameplay/presentation/score_float/score_float.tscn")
var view: BoardView
var ledger: ScoreLedger

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	ledger = ScoreLedger.new()
	view = VIEW.instantiate() as BoardView
	add_child_autofree(view)
	view.configure(9, 9, Vector2(64, 64), Vector2.ONE)

func after_each() -> void:
	get_tree().paused = false
	await wait_process_frames(2)

func test_split_uses_paid_main_score_and_exact_extra_without_mutating_entry() -> void:
	var result: MatchResult = _result(5, 1.51, 20, Vector2i(4, 4))
	var popup: ScoreFloat = _show(result)
	assert_eq(popup.score_label.text, "得分 +75")
	assert_eq(popup.formula_label.text, "50 × 1.51 → 75")
	assert_eq(popup.extra_label.text, "额外 +20")
	assert_true(popup.score_label.visible)
	assert_true(popup.extra_label.visible)
	assert_eq(ledger.total, 95)
	assert_eq(result.score_entry.final_score, 95)
	result.score_entry.extra_score = 900
	assert_eq(popup.extra_label.text, "额外 +20", "显示不跟随外部条目的后续修改")
	await wait_process_frames(2)
	assert_eq(popup.panel.size, popup.display_size, "碰撞排布使用真实容器尺寸")

func test_bonus_only_and_zero_score_never_invent_base_points() -> void:
	var bonus: MatchResult = _result(0, 1.0, 10, Vector2i(4, 4))
	bonus.cause = &"explosion"
	bonus.generation = 2
	var popup: ScoreFloat = _show(bonus)
	assert_false(popup.score_label.visible)
	assert_false(popup.formula_label.visible)
	assert_eq(popup.extra_label.text, "额外 +10")
	assert_eq(popup.title_label.text, "连锁 · 第2波")
	_show_results([_result(0, 1.0, 0, Vector2i.ZERO)])
	assert_eq(view.score_floats.get_child_count(), 1)
	assert_eq(ledger.total, 10)

func test_grade_and_panel_material_are_independent_of_second_instance_and_template() -> void:
	var normal: ScoreFloat = _show(_result(5, 1.0, 0, Vector2i(4, 4)))
	var high: ScoreFloat = _show(_result(5, 2.0, 0, Vector2i(5, 5)))
	var huge: ScoreFloat = _show(_result(5, 5.0, 0, Vector2i(6, 6)))
	assert_eq(normal.score_label.modulate, normal.config.normal_color)
	assert_eq(high.score_label.modulate, high.config.high_color)
	assert_eq(huge.score_label.modulate, huge.config.huge_color)
	assert_string_contains(high.title_label.text, "大得分")
	assert_string_contains(huge.title_label.text, "高能得分")
	var extra_only: ScoreFloat = _show(_result(0, 1.0, 300, Vector2i(6, 6)))
	assert_false(extra_only.score_label.visible)
	assert_eq(extra_only.extra_label.modulate, extra_only.config.huge_color)
	var template: ScoreFloat = FLOAT.instantiate() as ScoreFloat
	add_child_autofree(template)
	var original: StyleBoxFlat = template.panel.get_theme_stylebox("panel") as StyleBoxFlat
	var a: StyleBoxFlat = normal.panel.get_theme_stylebox("panel") as StyleBoxFlat
	var b: StyleBoxFlat = high.panel.get_theme_stylebox("panel") as StyleBoxFlat
	var old_color: Color = original.border_color
	assert_ne(a, b)
	assert_ne(a, original)
	a.border_color = Color.RED
	assert_ne(b.border_color, Color.RED)
	assert_eq(original.border_color, old_color)

func test_edge_anchors_bonus_followup_and_overlapping_rewards_stay_readable() -> void:
	var source: MatchResult = _result(5, 1.0, 0, Vector2i(8, 8))
	var first: ScoreFloat = _show(source)
	var bonus: MatchResult = _result(0, 1.0, 20, Vector2i.ZERO)
	bonus.removed.clear()
	bonus.cause = &"bonus"
	bonus.score_entry.root_action_id = source.score_entry.root_action_id
	var next: ScoreFloat = _show(bonus)
	assert_true(view.get_display_rect().encloses(first.reserved_rect))
	assert_true(view.get_display_rect().encloses(next.reserved_rect))
	assert_false(first.reserved_rect.intersects(next.reserved_rect))
	assert_gt(next.position.x, 300.0, "无离场奖励跟随同一行动位置，而非默认左上角")

func test_pause_low_effects_speed_and_expiry_preserve_ledger() -> void:
	var popup: ScoreFloat = _show(_result(5, 1.0, 0, Vector2i(4, 4)))
	await wait_process_frames(20)
	get_tree().paused = true
	var position_before: Vector2 = popup.position
	var alpha_before: float = popup.modulate.a
	await wait_process_frames(15)
	assert_eq(popup.position, position_before)
	assert_eq(popup.modulate.a, alpha_before)
	get_tree().paused = false
	view.set_low_effects(true)
	position_before = popup.position
	await wait_process_frames(10)
	assert_eq(popup.position, position_before)
	assert_eq(popup.scale, Vector2.ONE)
	view.presentation_speed = 20.0
	await wait_process_frames(12)
	assert_eq(view.score_floats.get_child_count(), 0)
	assert_eq(ledger.total, 50)

func test_delayed_rewards_reserve_motion_range_and_crowded_bursts_do_not_overlap() -> void:
	var first: ScoreFloat = _show(_result(5, 1.0, 20, Vector2i(4, 4)))
	await wait_process_frames(25)
	var second: ScoreFloat = _show(_result(5, 1.0, 20, Vector2i(4, 4)))
	await wait_process_frames(12)
	assert_false(first.panel.get_global_rect().intersects(second.panel.get_global_rect()))
	for index: int in range(10): _show(_result(5, 1.0, 20, Vector2i(4, 4)))
	await wait_process_frames(12)
	var cards: Array[Node] = view.score_floats.get_children()
	assert_lte(cards.size(), view.score_floats.config.maximum_visible)
	for a: int in range(cards.size()):
		for b: int in range(a + 1, cards.size()):
			assert_false((cards[a] as ScoreFloat).panel.get_global_rect().intersects((cards[b] as ScoreFloat).panel.get_global_rect()))

func test_float_tail_is_optional_duplicate_results_do_not_repeat_and_reset_clears_old_text() -> void:
	var result: MatchResult = _result(5, 1.0, 0, Vector2i(4, 4))
	_show_results([result, result])
	assert_eq(view.score_floats.get_child_count(), 1)
	assert_true(await view.wait_for_animations(), "漂字不加入规则表现屏障")
	view.cancel_animations()
	assert_eq(view.score_floats.get_child_count(), 0)
	_show_results([result])
	assert_eq(view.score_floats.get_child_count(), 0, "取消后同事件不重播")
	view.clear_display()
	_show_results([result])
	assert_eq(view.score_floats.get_child_count(), 1, "新局可以从同事件ID开始")
	view.clear_display()
	await wait_process_frames(15)
	assert_eq(view.score_floats.get_child_count(), 0)
	assert_eq(ledger.total, 50)

func _result(count: int, multiplier: float, extra: int, center: Vector2i) -> MatchResult:
	var result: MatchResult = MatchResult.new()
	result.center = center
	result.score_entry = ledger.commit(count, multiplier, extra, &"match", 7)
	var piece: PieceState = PieceState.new()
	piece.coordinate = center
	result.removed = [piece]
	return result

func _show(result: MatchResult) -> ScoreFloat:
	_show_results([result])
	return view.score_floats.get_child(-1) as ScoreFloat

func _show_results(results: Array[MatchResult]) -> void:
	view.score_floats.show_results(results, Vector2(65, 65), view.get_display_rect(), view.low_effects, view.presentation_speed)
