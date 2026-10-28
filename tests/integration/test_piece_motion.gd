extends GutTest

## Checks that local deformation preserves hit bounds, clocks and committed rules.
const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
var _view: BoardView
var _rules: BoardRules

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_rules = BoardRules.new(BoardState.new(6, 3), 5)
	_view = VIEW.instantiate() as BoardView
	_view.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(_view)
	_view.configure(6, 3, Vector2(64, 64), Vector2.ONE)

func after_each() -> void:
	get_tree().paused = false
	await wait_process_frames(2)

func _place() -> ChessPiece:
	var state: PieceState = _rules.place_piece(Vector2i.ZERO, 0)
	_view.rebuild(_rules.state.get_snapshot())
	return _view.get_piece(state.piece_id)

func _motion(piece: ChessPiece) -> Node2D:
	var visual: Node2D = piece.get_node_or_null("MotionVisuals") as Node2D
	assert_not_null(visual, "Stable visual-only deformation group is required")
	return visual

func test_birth_deforms_body_locally_and_preserves_ghost_opacity() -> void:
	var piece: ChessPiece = _place()
	var visual: Node2D = _motion(piece)
	if visual == null: return
	piece.is_ghost = true
	var bounds: Rect2 = piece.tooltip_region.get_rect()
	var animation: Tween = piece.spawn_animation(0.12)
	assert_ne(visual.scale.x, visual.scale.y)
	assert_eq(piece.tooltip_region.get_rect(), bounds)
	await animation.finished
	assert_eq(visual.scale, Vector2.ONE)
	assert_eq(piece.scale, Vector2.ONE)
	assert_almost_eq(piece.modulate.a, 0.5, 0.001)
	assert_eq(_rules.state.get_piece(piece.piece_id).coordinate, Vector2i.ZERO)

func test_landing_keeps_root_and_hit_area_still_and_does_not_affect_another_piece() -> void:
	var piece: ChessPiece = _place()
	var other: PieceState = _rules.place_piece(Vector2i(1, 0), 1)
	_view.show_piece(other, BoardView.PIECE_SCENE.instantiate() as ChessPiece)
	var visual: Node2D = _motion(piece)
	if visual == null: return
	var bounds: Rect2 = piece.tooltip_region.get_global_rect()
	var animation: Tween = piece.land()
	assert_eq(piece.scale, Vector2.ONE)
	assert_ne(visual.scale, Vector2.ONE)
	assert_eq(piece.tooltip_region.get_global_rect(), bounds)
	assert_eq((_view.get_piece(other.piece_id).get_node("MotionVisuals") as Node2D).scale, Vector2.ONE)
	await animation.finished
	assert_eq(visual.scale, Vector2.ONE)

func test_low_effects_during_birth_snaps_deformation_without_killing_required_clock() -> void:
	var piece: ChessPiece = _place()
	var visual: Node2D = _motion(piece)
	if visual == null: return
	var animation: Tween = piece.spawn_animation(0.4)
	_view.track_presentation(animation)
	await wait_process_frames(3)
	piece.set_low_effects(true)
	assert_eq(visual.scale, Vector2.ONE)
	assert_true(animation.is_running())
	await wait_process_frames(3)
	assert_eq(visual.scale, Vector2.ONE)
	assert_true(animation.is_running())
	await animation.finished
	assert_eq(piece.scale, Vector2.ONE)
	assert_eq(visual.scale, Vector2.ONE)

func test_pause_cancel_and_reset_restore_deformation_without_late_writes() -> void:
	var piece: ChessPiece = _place()
	var visual: Node2D = _motion(piece)
	if visual == null: return
	var animation: Tween = piece.spawn_animation(0.4)
	_view.track_presentation(animation)
	await wait_process_frames(3)
	get_tree().paused = true
	var pose: Vector2 = visual.scale
	await wait_process_frames(5)
	assert_eq(visual.scale, pose)
	get_tree().paused = false
	_view.cancel_animations()
	assert_eq(visual.scale, Vector2.ONE)
	piece.spawn_animation(0.2)
	piece.reset()
	await wait_seconds(0.3)
	assert_eq(visual.scale, Vector2.ONE)
	assert_eq(piece.scale, Vector2.ONE)
	assert_eq(piece.modulate.a, 1.0)

func test_move_landing_keeps_four_mode_rule_results_and_finishes_at_rest() -> void:
	var piece: ChessPiece = _place()
	if _motion(piece) == null: return
	for fast: bool in [false, true]:
		for reduced: bool in [false, true]:
			_view.presentation_speed = 4.0 if fast else 1.0
			_view.set_low_effects(reduced)
			var state: PieceState = _rules.state.get_piece(piece.piece_id)
			var destination: Vector2i = Vector2i(2, 0) if state.coordinate == Vector2i.ZERO else Vector2i.ZERO
			var result: BoardMoveResult = _rules.move_piece(piece.piece_id, destination)
			assert_true(await _view.animate_move(result, 0.12))
			piece = _view.get_piece(piece.piece_id)
			assert_eq((piece.get_node("MotionVisuals") as Node2D).scale, Vector2.ONE)
			assert_eq(piece.scale, Vector2.ONE)
			assert_eq(_rules.state.get_piece_count(), 1)
			assert_eq(_rules.state.get_piece(piece.piece_id).coordinate, destination)
			assert_eq(_view.get_cell(destination).piece, piece)

func test_birth_recovery_fits_inside_existing_duration_without_an_extra_tail() -> void:
	var piece: ChessPiece = _place()
	var visual: Node2D = _motion(piece)
	if visual == null: return
	var animation: Tween = piece.spawn_animation(0.12)
	animation.pause()
	watch_signals(animation)
	assert_true(animation.custom_step(0.115))
	assert_signal_not_emitted(animation, "finished")
	assert_ne(visual.scale, Vector2.ONE)
	animation.custom_step(0.01)
	assert_signal_emit_count(animation, "finished", 1)
	# The completion-producing step returns true; a subsequent step reports dead.
	assert_false(animation.custom_step(0.0))
	assert_eq(visual.scale, Vector2.ONE)
	assert_eq(piece.scale, Vector2.ONE)
