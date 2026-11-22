extends GutTest

## Verifies marker identity, isolated materials, and the pause-aware clock.
const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
const PIECE: PackedScene = preload("res://gameplay/board/piece/chess_piece.tscn")
var view: BoardView
var rules: BoardRules

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	view = VIEW.instantiate() as BoardView
	add_child_autofree(view)
	view.configure(2, 1, Vector2(64, 64), Vector2.ONE)
	rules = BoardRules.new(BoardState.new(2, 1), 5)
	rules.place_piece(Vector2i.ZERO, 0)
	rules.place_piece(Vector2i(1, 0), 3)
	view.rebuild(rules.state.get_snapshot())

func after_each() -> void:
	get_tree().paused = false
	await wait_process_frames(2)

func test_explosion_material_is_per_instance_and_tracks_body_without_faces() -> void:
	var a: ChessPiece = view.get_cell(Vector2i.ZERO).piece
	var b: ChessPiece = view.get_cell(Vector2i(1, 0)).piece
	a.set_ability_marker("爆")
	b.set_ability_marker("引")
	var first: ShaderMaterial = a.ability_visual.body_outline.material as ShaderMaterial
	var second: ShaderMaterial = b.ability_visual.body_outline.material as ShaderMaterial
	var template: ChessPiece = PIECE.instantiate() as ChessPiece
	autofree(template)
	var original: ShaderMaterial = (template.get_node("MotionVisuals/PieceAbilityVisual/BodyOutline") as Sprite2D).material as ShaderMaterial
	var initial: Variant = original.get_shader_parameter("phase")
	assert_ne(first, second)
	assert_ne(first, original)
	first.set_shader_parameter("phase", 0.9)
	assert_ne(second.get_shader_parameter("phase"), 0.9)
	assert_eq(original.get_shader_parameter("phase"), initial)
	assert_same(a.ability_visual.body_outline.texture, NutVisual.BODIES[0])
	a.piece_type = 4
	assert_same(a.ability_visual.body_outline.texture, NutVisual.BODIES[4])
	assert_same(b.ability_visual.body_outline.texture, NutVisual.BODIES[3])
	assert_false(a.ability_visual.first_arrow.visible)
	assert_false(a.ability_marker.visible)
	assert_eq(rules.state.get_piece_at(Vector2i.ZERO).match_color, 0)

func test_arrow_axes_pause_and_reduced_effects_keep_static_identity() -> void:
	var row: ChessPiece = view.get_cell(Vector2i.ZERO).piece
	var column: ChessPiece = view.get_cell(Vector2i(1, 0)).piece
	row.set_ability_marker("行")
	column.set_ability_marker("列")
	row.selected()
	await wait_process_frames(8)
	assert_gt(row.ability_visual.first_arrow.position.x, 0.0)
	assert_eq(row.ability_visual.first_arrow.position.y, 0.0)
	assert_gt(column.ability_visual.first_arrow.position.y, 0.0)
	assert_almost_eq(column.ability_visual.first_arrow.rotation, PI * 0.5, 0.001)
	var position_before: Vector2 = row.ability_visual.first_arrow.position
	var energy_before: float = row.ability_visual.energy
	get_tree().paused = true
	await wait_process_frames(8)
	assert_eq(row.ability_visual.energy, energy_before)
	assert_eq(row.ability_visual.first_arrow.position, position_before)
	get_tree().paused = false
	view.set_low_effects(true)
	assert_eq(row.ability_visual.energy, 0.0)
	assert_true(row.ability_visual.first_arrow.visible)
	assert_true(column.ability_visual.second_arrow.visible)
	assert_true(row.aura.visible)
	assert_eq(row.aura.corners.size(), 4)
	var static_position: Vector2 = row.ability_visual.first_arrow.position
	await wait_process_frames(8)
	assert_eq(row.ability_visual.first_arrow.position, static_position)
	assert_eq(row.aura.get("_energy"), 0.0)
	row.set_ability_marker("")
	assert_false(row.ability_visual.visible)
	assert_eq(rules.state.get_piece_count(), 2)

func test_core_and_fuse_keep_distinct_static_contours_when_reused_or_reduced() -> void:
	var piece: ChessPiece = view.get_cell(Vector2i.ZERO).piece
	var other: ChessPiece = view.get_cell(Vector2i(1, 0)).piece
	var config: PieceMarkerConfig = piece.ability_visual.config
	var before: Array[PieceState] = rules.state.get_snapshot()
	piece.set_ability_marker("爆")
	other.set_ability_marker("引")
	var first: ShaderMaterial = piece.ability_visual.body_outline.material as ShaderMaterial
	var second: ShaderMaterial = other.ability_visual.body_outline.material as ShaderMaterial
	await wait_process_frames(8)
	var phase: float = float(second.get_shader_parameter("phase"))
	assert_gt(phase, 0.0)
	get_tree().paused = true
	await wait_process_frames(8)
	assert_eq(second.get_shader_parameter("phase"), phase)
	get_tree().paused = false
	view.set_low_effects(true)
	assert_false(first.get_shader_parameter("fuse_mark"))
	assert_true(second.get_shader_parameter("fuse_mark"))
	assert_true(first.get_shader_parameter("steady"))
	assert_true(second.get_shader_parameter("steady"))
	assert_eq(first.get_shader_parameter("outline_width"), config.outline_width)
	assert_eq(first.get_shader_parameter("rim_width"), config.outline_rim_width)
	assert_eq(first.get_shader_parameter("phase"), 0.0)
	assert_true(piece.ability_visual.body_outline.visible)
	assert_true(other.ability_visual.body_outline.visible)
	await wait_process_frames(8)
	assert_eq(second.get_shader_parameter("phase"), 0.0)
	piece.set_ability_marker("引")
	assert_true(first.get_shader_parameter("fuse_mark"))
	other.set_ability_marker("行")
	assert_false(second.get_shader_parameter("fuse_mark"))
	assert_false(other.ability_visual.body_outline.visible)
	assert_true(other.ability_visual.first_arrow.visible)
	assert_eq(rules.state.get_snapshot().size(), before.size())
	assert_eq(rules.state.get_piece_at(Vector2i.ZERO).match_color, 0)

func test_only_new_fuse_marks_flash_and_keep_their_steady_marker_afterwards(
	reduced: bool = use_parameters([false, true])
) -> void:
	var fresh: ChessPiece = view.get_cell(Vector2i.ZERO).piece
	var existing: ChessPiece = view.get_cell(Vector2i(1, 0)).piece
	view.set_low_effects(reduced)
	view.show_ability_marker(existing.piece_id, "引")
	var marks: Array[PieceState] = [rules.state.get_piece(fresh.piece_id).copy()]
	view.show_fuse_marks(marks, 0.15)
	assert_eq((fresh.get_node("FuseSpark") as Node2D).visible, not reduced)
	assert_false((existing.get_node("FuseSpark") as Node2D).visible)
	assert_false((fresh.get_node("ConversionBurst") as Polygon2D).visible)
	await view.wait_for_animations()
	assert_false((fresh.get_node("FuseSpark") as Node2D).visible)
	assert_eq(fresh.ability_visual.kind, &"引")
	assert_eq(existing.ability_visual.kind, &"引")

func test_core_conversion_uses_burst_and_reset_clears_it() -> void:
	var piece: ChessPiece = view.get_cell(Vector2i.ZERO).piece
	var converted: PieceState = rules.state.get_piece(piece.piece_id).copy()
	converted.content_id = &"special_demolition"
	view.animate_transform(converted, 0.15)
	var burst: Polygon2D = piece.get_node("ConversionBurst")
	assert_true(burst.visible)
	assert_false((piece.get_node("FuseSpark") as Node2D).visible)
	assert_eq(piece.ability_visual.kind, &"爆")
	piece.reset()
	assert_false(burst.visible)
	view.set_low_effects(true)
	view.animate_transform(converted, 0.15)
	assert_false(burst.visible)
	assert_eq(piece.ability_visual.kind, &"爆")

func test_sweep_arrows_follow_the_upgraded_axis_and_stay_clear_in_low_effects() -> void:
	var row: ChessPiece = view.get_cell(Vector2i.ZERO).piece
	var column: ChessPiece = view.get_cell(Vector2i(1, 0)).piece
	var snapshots: Array[PieceState] = rules.state.get_snapshot()
	snapshots[0].content_id = LineClearState.CONTENT_ROW
	snapshots[1].content_id = LineClearState.CONTENT_COLUMN
	var explosion: ExplosionState = ExplosionState.new()
	var config: ExplosionConfig = preload("res://gameplay/skills/content/explosion_config.tres")
	var spans: LineClearState = LineClearState.new()

	view.refresh_piece_details(snapshots, explosion, config, spans)
	_assert_sweep_pair(row.ability_visual)
	_assert_sweep_pair(column.ability_visual)

	spans.upgrades[&"line_row_span"] = 1
	view.refresh_piece_details(snapshots, explosion, config, spans)
	_assert_sweep_triple(row.ability_visual, Vector2.RIGHT)
	_assert_sweep_pair(column.ability_visual)

	spans.upgrades[&"line_column_span"] = 1
	view.animate_transform(snapshots[1], 0.0, spans)
	_assert_sweep_triple(column.ability_visual, Vector2.DOWN)
	view.set_low_effects(true)
	var row_position: Vector2 = row.ability_visual.third_arrow.position
	var column_position: Vector2 = column.ability_visual.third_arrow.position
	await wait_process_frames(8)
	_assert_sweep_triple(row.ability_visual, Vector2.RIGHT)
	_assert_sweep_triple(column.ability_visual, Vector2.DOWN)
	assert_eq(row.ability_visual.third_arrow.position, row_position)
	assert_eq(column.ability_visual.third_arrow.position, column_position)
	assert_eq(row.ability_visual.energy, 0.0)
	assert_eq(column.ability_visual.energy, 0.0)

	spans.upgrades.clear()
	view.refresh_piece_details(snapshots, explosion, config, spans)
	_assert_sweep_pair(row.ability_visual)
	_assert_sweep_pair(column.ability_visual)

func _assert_sweep_pair(visual: PieceAbilityVisual) -> void:
	assert_true(visual.first_arrow.visible)
	assert_true(visual.second_arrow.visible)
	assert_false(visual.third_arrow.visible)
	assert_almost_eq(visual.second_arrow.rotation - visual.first_arrow.rotation, PI, 0.001)
	assert_eq(visual.second_arrow.position, -visual.first_arrow.position)

func _assert_sweep_triple(visual: PieceAbilityVisual, axis: Vector2) -> void:
	var arrows: Array[Sprite2D] = [visual.first_arrow, visual.second_arrow, visual.third_arrow]
	var separation: Vector2 = arrows[1].position - arrows[0].position
	for arrow: Sprite2D in arrows:
		assert_true(arrow.visible)
		assert_almost_eq(arrow.rotation, axis.angle(), 0.001)
	assert_gt(separation.length(), visual.config.arrow_size.y)
	assert_almost_eq(separation.dot(axis), 0.0, 0.001)
	assert_almost_eq(arrows[2].position - arrows[1].position, separation, Vector2.ONE * 0.001)
