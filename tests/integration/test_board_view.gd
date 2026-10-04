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
