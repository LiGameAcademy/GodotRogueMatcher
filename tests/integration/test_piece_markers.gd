extends GutTest

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
	var original: ShaderMaterial = (template.get_node("PieceAbilityVisual/BodyOutline") as Sprite2D).material as ShaderMaterial
	var initial: Variant = original.get_shader_parameter("energy")
	assert_ne(first, second)
	assert_ne(first, original)
	first.set_shader_parameter("energy", 0.9)
	assert_ne(second.get_shader_parameter("energy"), 0.9)
	assert_eq(original.get_shader_parameter("energy"), initial)
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
