extends GutTest

const VIEW_SCENE: PackedScene = preload("res://gameplay/board/board_view.tscn")
var view: BoardView
var rules: BoardRules

func before_each() -> void:
	rules = BoardRules.new(BoardState.new(6, 3), 5)
	view = VIEW_SCENE.instantiate() as BoardView
	add_child_autofree(view)
	view.configure(6, 3, Vector2(64, 64), Vector2.ONE)

func after_each() -> void:
	await wait_process_frames(2)

func test_standalone_view_renders_without_external_parent_state() -> void:
	var first: PieceState = rules.place_piece(Vector2i(5, 2), 0)
	var second: PieceState = rules.place_piece(Vector2i.ZERO, 1)
	view.rebuild(rules.state.get_snapshot())
	assert_eq(view.get_cells().size(), 18)
	assert_eq(view.get_cell(first.coordinate).piece.piece_id, first.piece_id)
	assert_eq(view.get_cell(second.coordinate).piece.piece_type, second.match_color)
	assert_eq(view.get_cell(Vector2i(5, 2)).position, Vector2(325, 130))
	assert_null(view.get_cell(Vector2i(6, 2)))

func test_click_only_emits_coordinate_without_moving_rules() -> void:
	var piece: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	watch_signals(view)
	view.get_cell(Vector2i(1, 0)).pressed.emit(view.get_cell(Vector2i(1, 0)))
	assert_signal_emitted_with_parameters(view, "cell_pressed", [Vector2i(1, 0)])
	assert_eq(rules.state.get_piece(piece.piece_id).coordinate, Vector2i.ZERO)

func test_rebuilding_display_preserves_rule_ids_and_colors() -> void:
	var first: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	var previous_display: ChessPiece = view.get_piece(first.piece_id)
	previous_display.piece_type = 4
	assert_eq(rules.state.get_piece(first.piece_id).match_color, 0)
	view.rebuild(rules.state.get_snapshot())
	assert_ne(view.get_piece(first.piece_id), previous_display)
	assert_eq(view.get_piece(first.piece_id).piece_type, 0)
	assert_eq(rules.state.get_piece_count(), 1)
	var next: PieceState = rules.place_piece(Vector2i(1, 0), 1)
	assert_eq(next.piece_id, first.piece_id + 1)

func test_animation_consumes_already_committed_move_result() -> void:
	var piece: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	var result: BoardMoveResult = rules.move_piece(piece.piece_id, Vector2i(2, 0))
	assert_eq(rules.state.get_piece(piece.piece_id).coordinate, Vector2i(2, 0))
	await view.animate_move(result, 0.03)
	assert_null(view.get_cell(Vector2i.ZERO).piece)
	assert_eq(view.get_cell(Vector2i(2, 0)).piece.piece_id, piece.piece_id)
	assert_eq(rules.state.get_piece(piece.piece_id).coordinate, Vector2i(2, 0))

func test_rebuild_cancels_old_animation_without_altering_rule_state() -> void:
	var piece: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	var result: BoardMoveResult = rules.move_piece(piece.piece_id, Vector2i(2, 0))
	view.animate_move(result, 0.5)
	view.rebuild(rules.state.get_snapshot())
	await get_tree().create_timer(0.6).timeout
	assert_eq(view.get_cell(Vector2i(2, 0)).piece.piece_id, piece.piece_id)
	assert_null(view.get_cell(Vector2i.ZERO).piece)
	assert_eq(rules.state.get_piece_count(), 1)

func test_two_views_do_not_share_mutable_materials() -> void:
	var piece: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	var second: BoardView = VIEW_SCENE.instantiate() as BoardView
	add_child_autofree(second)
	second.configure(6, 3, Vector2(64, 64), Vector2.ONE)
	second.rebuild(rules.state.get_snapshot())
	var first_material: ParticleProcessMaterial = view.get_piece(piece.piece_id).glow_particles.process_material as ParticleProcessMaterial
	var second_material: ParticleProcessMaterial = second.get_piece(piece.piece_id).glow_particles.process_material as ParticleProcessMaterial
	assert_ne(first_material, second_material)
	first_material.color = Color.BLUE
	assert_ne(second_material.color, Color.BLUE)

func test_special_tooltips_follow_current_ability_configuration() -> void:
	var run: RunController = RunController.new(rules, 11)
	var core: PieceState = run.abilities.add_core(Vector2i.ZERO)
	var fuse: PieceState = rules.place_piece(Vector2i(1, 0), 0)
	var ordinary: PieceState = rules.place_piece(Vector2i(2, 0), 2)
	assert_true(run.abilities.assign_fuse(fuse.piece_id))
	view.rebuild(rules.state.get_snapshot())
	view.refresh_piece_details(rules.state.get_snapshot(), run.state.explosion, run.abilities.config)
	assert_string_contains(view.get_piece(core.piece_id).tooltip_region.tooltip_text, "爆壳手")
	assert_string_contains(view.get_piece(core.piece_id).tooltip_region.tooltip_text, "3×3")
	assert_string_contains(view.get_piece(fuse.piece_id).tooltip_region.tooltip_text, "引信棋子")
	assert_string_contains(view.get_piece(fuse.piece_id).tooltip_region.tooltip_text, "红色")
	assert_eq(view.get_piece(ordinary.piece_id).tooltip_region.tooltip_text, "")
	assert_eq(view.get_piece(core.piece_id).tooltip_region.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(view.get_piece(ordinary.piece_id).tooltip_region.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(run.abilities.upgrade_radius())
	assert_true(run.abilities.upgrade_reward())
	run.state.explosion.blast_extra_level = 2
	view.refresh_piece_details(rules.state.get_snapshot(), run.state.explosion, run.abilities.config)
	var text: String = view.get_piece(core.piece_id).tooltip_region.tooltip_text
	assert_string_contains(text, "5×5")
	assert_string_contains(text, "每清除一枚目标 +5 分")
	assert_string_contains(text, "另加 10 分")
	assert_false(text.contains("双击"), "未实现的主动能力不能出现在提示中")
	assert_eq(run.state.ledger.total, 0, "生成提示不得结算分数")
	assert_eq(rules.state.get_piece_count(), 3)
	assert_false(run.state.explosion.instances[core.piece_id].has_triggered)

func test_tooltip_moves_with_piece_and_is_disabled_before_departure() -> void:
	var run: RunController = RunController.new(rules, 11)
	var core: PieceState = run.abilities.add_core(Vector2i.ZERO)
	view.rebuild(rules.state.get_snapshot())
	view.refresh_piece_details(rules.state.get_snapshot(), run.state.explosion, run.abilities.config)
	var display: ChessPiece = view.get_piece(core.piece_id)
	var result: BoardMoveResult = rules.move_piece(core.piece_id, Vector2i(2, 0))
	await view.animate_move(result, 0.03)
	assert_eq(display.get_parent(), view.get_cell(Vector2i(2, 0)))
	assert_string_contains(display.tooltip_region.tooltip_text, "爆壳手")
	view.remove_piece(rules.state.get_piece(core.piece_id), true)
	assert_eq(display.tooltip_region.tooltip_text, "")
	assert_eq(display.tooltip_region.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(await view.wait_for_animations())

func test_rebuild_does_not_reuse_old_run_tooltip_for_same_piece_id() -> void:
	var run: RunController = RunController.new(rules, 11)
	var core: PieceState = run.abilities.add_core(Vector2i.ZERO)
	view.rebuild(rules.state.get_snapshot())
	view.refresh_piece_details(rules.state.get_snapshot(), run.state.explosion, run.abilities.config)
	assert_false(view.get_piece(core.piece_id).tooltip_region.tooltip_text.is_empty())
	var next_rules: BoardRules = BoardRules.new(BoardState.new(6, 3), 5)
	var ordinary: PieceState = next_rules.place_piece(Vector2i.ZERO, 4)
	assert_eq(ordinary.piece_id, core.piece_id)
	view.rebuild(next_rules.state.get_snapshot())
	view.refresh_piece_details(next_rules.state.get_snapshot(), ExplosionState.new(), run.abilities.config)
	assert_eq(view.get_piece(ordinary.piece_id).tooltip_region.tooltip_text, "")
	assert_false(view.get_piece(ordinary.piece_id).ability_marker.visible)

func test_dye_step_changes_visual_color_before_following_match_without_rule_mutation() -> void:
	var run: RunController = RunController.new(rules, 7)
	var piece: PieceState = rules.place_piece(Vector2i.ZERO, 2)
	view.rebuild(rules.state.get_snapshot())
	var results: Array[MatchResult] = DyeRules.recolor(run.abilities, [piece.piece_id], 0)
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches(results)
	rules.set_piece_color(piece.piece_id, 1)
	view.animate_matches(steps[0].matches)
	await view.wait_for_presentation()
	assert_eq(view.get_piece(piece.piece_id).piece_type, 0)
	assert_eq(rules.state.get_piece(piece.piece_id).match_color, 1)
	assert_eq(steps[0].matches[0].recolored[0].match_color, 0)
