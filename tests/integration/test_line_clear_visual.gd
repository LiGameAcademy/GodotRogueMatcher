extends GutTest

const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
var view: BoardView
var rules: BoardRules

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	rules = BoardRules.new(BoardState.new(6, 3), 5)
	view = VIEW.instantiate() as BoardView
	add_child_autofree(view)
	view.configure(6, 3, Vector2(64, 64), Vector2.ONE)

func after_each() -> void:
	get_tree().paused = false
	view.cancel_animations()
	await wait_process_frames(2)

func _visuals() -> Array[LineClearVisual]:
	var result: Array[LineClearVisual] = []
	for child: Node in view.get_children():
		if child is LineClearVisual: result.append(child as LineClearVisual)
	return result

func test_frozen_row_and_column_results_draw_full_axis_even_with_no_targets() -> void:
	for axis: int in [0, 1]:
		var run: RunController = RunController.new(rules, 74)
		var source: PieceState = run.abilities.add_line_piece(axis, Vector2i(2, 1), 0)
		view.rebuild(rules.state.get_snapshot())
		var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"consume")
		var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches(results)
		results[0].line_axis = 1 - axis
		results[0].center = Vector2i.ZERO
		view.remove_piece(source)
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		view.animate_matches(steps[0].matches)
		assert_eq(_visuals().size(), 1)
		var visual: LineClearVisual = _visuals()[0]
		assert_eq(visual.get("_axis"), axis)
		var area: Rect2 = visual.get("_area")
		assert_eq(area, Rect2(-32, 33, 389, 64) if axis == 0 else Rect2(98, -32, 64, 194))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
		assert_true(await view.wait_for_animations())
		await wait_process_frames(2)
		assert_eq(_visuals().size(), 0)

func test_pause_fast_playback_and_cancellation_keep_rules_unchanged() -> void:
	var run: RunController = RunController.new(rules, 74)
	var source: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	view.show_line_clear(Vector2i.ZERO, 0)
	var visual: LineClearVisual = _visuals()[0]
	await wait_process_frames(2)
	get_tree().paused = true
	var progress: float = visual.get("_progress")
	await wait_process_frames(10)
	assert_eq(visual.get("_progress"), progress)
	get_tree().paused = false
	view.presentation_speed = 8.0
	assert_true(await view.wait_for_animations())
	await wait_process_frames(2)
	assert_eq(_visuals().size(), 0)
	view.show_line_clear(Vector2i.ZERO, 1)
	view.cancel_animations()
	assert_false(view.is_presenting())
	assert_eq(_visuals().size(), 0)
	assert_not_null(view.get_piece(source.piece_id))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_low_effects_and_retry_cleanup_cover_both_sweep_instances() -> void:
	view.show_line_clear(Vector2i.ZERO, 0)
	view.show_line_clear(Vector2i(2, 1), 1)
	assert_eq(_visuals().size(), 2)
	view.set_low_effects(true)
	for visual: LineClearVisual in _visuals(): assert_true(visual.low_effects)
	view.clear_display()
	assert_eq(_visuals().size(), 0)
	assert_false(view.is_presenting())

func test_wide_visual_uses_frozen_radius_and_clips_to_the_board() -> void:
	for axis: int in [0, 1]:
		var run: RunController = RunController.new(rules, 75)
		run.state.line_clear.upgrades[LineClearRules.upgrade_for_axis(axis)] = 1
		var source: PieceState = run.abilities.add_line_piece(axis, Vector2i(2, 1), 0)
		view.rebuild(rules.state.get_snapshot())
		var result: MatchResult = run.abilities.resolve_removal([source], &"consume")[0]
		var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches([result])
		result.radius = 0
		run.state.line_clear.upgrades.clear()
		view.remove_piece(source)
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		view.animate_matches(steps[0].matches)
		var area: Rect2 = _visuals()[0].get("_area")
		assert_eq(area, Rect2(-32, -32, 389, 194) if axis == 0 else Rect2(33, -32, 194, 194))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
		view.cancel_animations()
		view.show_line_clear(Vector2i.ZERO, axis, 1)
		area = _visuals()[0].get("_area")
		assert_eq(area, Rect2(-32, -32, 389, 129) if axis == 0 else Rect2(-32, -32, 129, 194))
		view.cancel_animations()

func test_skip_sweep_removes_only_frozen_targets_without_resolving_again() -> void:
	var run: RunController = RunController.new(rules, 74)
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	var target: PieceState = rules.place_piece(Vector2i(1, 0), 1)
	var survivor: PieceState = rules.place_piece(Vector2i(1, 1), 2)
	view.rebuild(rules.state.get_snapshot())
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches(run.abilities.resolve_removal([source], &"consume"))
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	view.remove_piece(source)
	view.animate_matches(steps[0].matches)
	assert_eq(steps[0].policy, PresentationStep.Policy.SKIPPABLE)
	assert_true(view.skip_step(steps[0]))
	assert_eq(_visuals().size(), 0)
	assert_null(view.get_piece(target.piece_id))
	assert_not_null(view.get_piece(survivor.piece_id))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_cross_visual_freezes_both_independent_bands_and_cancels_together() -> void:
	var run: RunController = RunController.new(rules, 75)
	run.state.line_clear.upgrades = {&"line_cross_upgrade": 1, &"line_row_span": 1}
	var source: PieceState = run.abilities.add_line_piece(1, Vector2i(2, 1), 0)
	view.rebuild(rules.state.get_snapshot())
	var result: MatchResult = run.abilities.resolve_removal([source], &"consume")[0]
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches([result])
	result.cross_radius = -1
	run.state.line_clear.upgrades.clear()
	view.remove_piece(source)
	view.animate_matches(steps[0].matches)
	assert_eq(_visuals().size(), 1)
	var visual: LineClearVisual = _visuals()[0]
	assert_eq(visual.get("_area"), Rect2(98, -32, 64, 194))
	assert_eq(visual.get("_second_area"), Rect2(-32, -32, 389, 194))
	view.set_low_effects(true)
	assert_true(visual.low_effects)
	assert_true(view.skip_step(steps[0]))
	assert_eq(_visuals().size(), 0)

func test_unlocked_sweeper_tooltip_is_localized_and_does_not_mutate_state() -> void:
	var run: RunController = RunController.new(rules, 74)
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 2)
	run.state.line_clear.upgrades[&"line_manual_clear"] = 1
	view.rebuild(rules.state.get_snapshot())
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en_US")
	view.refresh_piece_details(rules.state.get_snapshot(), run.state.explosion, run.abilities.config, run.state.line_clear)
	assert_string_contains(view.get_piece(source.piece_id).tooltip_region.tooltip_text, "Double-click to sweep")
	TranslationServer.set_locale(locale)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
