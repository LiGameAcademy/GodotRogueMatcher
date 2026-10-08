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
	assert_eq(popup.score_label.text, "+75")
	assert_null(popup.get_node_or_null("Panel"))
	assert_eq(popup.extra_label.text, "+20")
	assert_true(popup.score_label.visible)
	assert_true(popup.extra_label.visible)
	assert_eq(ledger.total, 95)
	assert_eq(result.score_entry.final_score, 95)
	result.score_entry.extra_score = 900
	assert_eq(popup.extra_label.text, "+20", "显示不跟随外部条目的后续修改")
	await wait_process_frames(2)
	assert_lt(popup.display_size.x, 110.0, "普通收益为紧凑数字")

func test_bonus_only_and_zero_score_never_invent_base_points() -> void:
	var bonus: MatchResult = _result(0, 1.0, 10, Vector2i(4, 4))
	bonus.cause = &"explosion"
	bonus.generation = 2
	var popup: ScoreFloat = _show(bonus)
	assert_false(popup.score_label.visible)
	assert_eq(popup.extra_label.position, Vector2.ZERO)
	assert_eq(popup.extra_label.text, "+10")
	assert_eq(popup.get_node("Numbers").get_child_count(), 2, "只有两组数字节点")
	_show_results([_result(0, 1.0, 0, Vector2i.ZERO)])
	assert_eq(view.score_floats.get_child_count(), 1)
	assert_eq(ledger.total, 10)

func test_grade_font_and_colors_are_isolated_per_number_instance() -> void:
	var normal: ScoreFloat = _show(_result(5, 1.0, 0, Vector2i(4, 4)))
	var high: ScoreFloat = _show(_result(5, 2.0, 0, Vector2i(5, 5)))
	var huge: ScoreFloat = _show(_result(5, 5.0, 0, Vector2i(6, 6)))
	assert_eq(normal.score_label.modulate, normal.config.normal_color)
	assert_eq(high.score_label.modulate, high.config.high_color)
	assert_eq(huge.score_label.modulate, huge.config.huge_color)
	assert_eq(normal.score_label.get_theme_font_size("font_size"), normal.config.normal_font_size)
	assert_eq(high.score_label.get_theme_font_size("font_size"), high.config.high_font_size)
	assert_eq(huge.score_label.get_theme_font_size("font_size"), huge.config.huge_font_size)
	var extra_only: ScoreFloat = _show(_result(0, 1.0, 300, Vector2i(6, 6)))
	assert_false(extra_only.score_label.visible)
	assert_eq(extra_only.extra_label.modulate, extra_only.config.huge_color)
	var template: ScoreFloat = FLOAT.instantiate() as ScoreFloat
	add_child_autofree(template)
	normal.score_label.add_theme_font_size_override("font_size", 12)
	assert_eq(high.score_label.get_theme_font_size("font_size"), high.config.high_font_size)
	assert_eq(template.score_label.get_theme_font_size("font_size"), 20)

func test_big_scores_pop_more_and_stay_inside_reserved_sweep() -> void:
	var high: ScoreFloat = _show(_result(5, 2.0, 0, Vector2i(8, 0)))
	var huge: ScoreFloat = _show(_result(5, 5.0, 0, Vector2i(8, 0)))
	var high_peak: float = 0.0
	var huge_peak: float = 0.0
	for frame: int in range(35):
		await wait_process_frames(1)
		high_peak = maxf(high_peak, high.numbers.scale.x)
		huge_peak = maxf(huge_peak, huge.numbers.scale.x)
		assert_true(high.reserved_rect.grow(0.01).encloses(high.numbers.get_global_rect()))
		assert_true(huge.reserved_rect.grow(0.01).encloses(huge.numbers.get_global_rect()))
	assert_gt(high_peak, 1.2)
	assert_gt(huge_peak, high_peak)
	assert_eq(high.numbers.scale, Vector2.ONE)
	assert_eq(huge.numbers.scale, Vector2.ONE)
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
	assert_eq(popup.numbers.scale, Vector2.ONE)
	view.presentation_speed = 20.0
	await wait_process_frames(12)
	assert_eq(view.score_floats.get_child_count(), 0)
	assert_eq(ledger.total, 50)

func test_delayed_rewards_reserve_motion_range_and_crowded_bursts_do_not_overlap() -> void:
	var first: ScoreFloat = _show(_result(5, 1.0, 20, Vector2i(4, 4)))
	await wait_process_frames(25)
	var second: ScoreFloat = _show(_result(5, 1.0, 20, Vector2i(4, 4)))
	await wait_process_frames(12)
	assert_false(first.numbers.get_global_rect().intersects(second.numbers.get_global_rect()))
	for index: int in range(10): _show(_result(5, 1.0, 20, Vector2i(4, 4)))
	await wait_process_frames(12)
	var cards: Array[Node] = view.score_floats.get_children()
	assert_lte(cards.size(), view.score_floats.config.maximum_visible)
	for a: int in range(cards.size()):
		for b: int in range(a + 1, cards.size()):
			assert_false((cards[a] as ScoreFloat).numbers.get_global_rect().intersects((cards[b] as ScoreFloat).numbers.get_global_rect()))

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
