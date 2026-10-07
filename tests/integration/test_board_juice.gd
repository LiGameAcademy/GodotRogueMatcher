extends GutTest

const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
const PIECE: PackedScene = preload("res://gameplay/board/piece/chess_piece.tscn")
const CELL: PackedScene = preload("res://gameplay/board/cell/cell.tscn")
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
	await wait_process_frames(2)

func test_piece_flash_isolated_from_other_instance_and_template() -> void:
	var first: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	var second: PieceState = rules.place_piece(Vector2i(1, 0), 1)
	view.rebuild(rules.state.get_snapshot())
	var template: ChessPiece = PIECE.instantiate() as ChessPiece
	autofree(template)
	var original: ShaderMaterial = (template.get_node("Polygon2D") as Polygon2D).material as ShaderMaterial
	var a: ShaderMaterial = view.get_piece(first.piece_id).polygon.material as ShaderMaterial
	var b: ShaderMaterial = view.get_piece(second.piece_id).polygon.material as ShaderMaterial
	var initial: Variant = original.get_shader_parameter("flash")
	assert_ne(a, b)
	assert_ne(a, original)
	assert_eq(a.shader, b.shader)
	a.set_shader_parameter("flash", 0.9)
	assert_ne(b.get_shader_parameter("flash"), 0.9)
	assert_eq(original.get_shader_parameter("flash"), initial)

func test_tile_highlight_isolated_from_other_instance_and_template() -> void:
	var template: Cell = CELL.instantiate() as Cell
	autofree(template)
	var original: ShaderMaterial = (template.get_node("Background") as ColorRect).material as ShaderMaterial
	var initial: Variant = original.get_shader_parameter("edge_color")
	var other: ShaderMaterial = view.get_cell(Vector2i(1, 0)).background.material as ShaderMaterial
	var other_initial: Variant = other.get_shader_parameter("edge_color")
	view.get_cell(Vector2i.ZERO).highlight_path()
	assert_ne(view.get_cell(Vector2i.ZERO).background.material, other)
	assert_eq(other.get_shader_parameter("edge_color"), other_initial)
	assert_eq(original.get_shader_parameter("edge_color"), initial)

func test_birth_keeps_ghost_alpha_and_never_modifies_rule_piece() -> void:
	var state: PieceState = rules.place_piece(Vector2i.ZERO, 2, &"", true)
	view.rebuild(rules.state.get_snapshot())
	var piece: ChessPiece = view.get_piece(state.piece_id)
	await piece.spawn_animation(0.04).finished
	assert_almost_eq(piece.modulate.a, 0.5, 0.001)
	assert_eq(piece.scale, Vector2.ONE)
	assert_eq(rules.state.get_piece_count(), 1)
	assert_eq(rules.state.get_piece(state.piece_id).coordinate, Vector2i.ZERO)
	assert_true(rules.state.get_piece(state.piece_id).is_ghost)

func test_cancel_move_clears_path_and_keeps_committed_rules() -> void:
	var state: PieceState = rules.place_piece(Vector2i.ZERO, 0)
	view.rebuild(rules.state.get_snapshot())
	var result: BoardMoveResult = rules.move_piece(state.piece_id, Vector2i(2, 0))
	view.animate_move(result, 0.6)
	assert_true(view.get_cell(Vector2i(1, 0)).is_path_highlighted)
	view.cancel_animations()
	await wait_process_frames(2)
	for cell: Cell in view.get_cells(): assert_false(cell.is_path_highlighted)
	assert_false(view.is_presenting())
	assert_eq(rules.state.get_piece(state.piece_id).coordinate, Vector2i(2, 0))
	assert_true(view.align_snapshot(rules.state.get_snapshot()))
	assert_eq(view.get_cell(Vector2i(2, 0)).piece.piece_id, state.piece_id)

func test_selection_pulse_pauses_and_low_effects_stops_motion() -> void:
	var state: PieceState = rules.place_piece(Vector2i.ZERO, 4)
	view.rebuild(rules.state.get_snapshot())
	var piece: ChessPiece = view.get_piece(state.piece_id)
	piece.selected()
	await wait_process_frames(10)
	var pulse: Tween = piece.aura.get("_pulse") as Tween
	assert_true(pulse.is_valid())
	get_tree().paused = true
	var energy: float = piece.aura.get("_energy")
	await wait_process_frames(10)
	assert_eq(piece.aura.get("_energy"), energy)
	get_tree().paused = false
	view.set_low_effects(true)
	await wait_process_frames(10)
	assert_false(pulse.is_valid())
	assert_eq(piece.aura.get("_energy"), 0.0)
	assert_true(piece.is_selected)
	assert_eq(rules.state.get_piece_count(), 1)
	assert_eq(rules.state.get_piece(state.piece_id).match_color, 4)
