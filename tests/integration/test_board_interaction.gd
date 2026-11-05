extends GutTest

## Exercises confirmed selection input, read-only previews and movement cleanup.
const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
const MAIN: PackedScene = preload("res://main.tscn")
const INTERACTION: Script = preload("res://gameplay/board/board_interaction.gd")
var _board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	var main: Node2D = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	(main.get_node("Game/Board") as Board).game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	_board = main.get_node("Game/Board") as Board
	await _board.initialized
	for piece: PieceState in _board.rules.state.get_snapshot(): _board.remove_piece(piece.coordinate)
	_place(Vector2i.ZERO)
	_place(Vector2i(8, 8))

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_reclick_cancels_and_switching_preserves_rules_and_random_streams() -> void:
	var action: int = _board.run.state.action_id
	var random_before: String = RunSnapshot.digest(_board.run.state.random_streams.data())
	_board._on_coordinate_pressed(Vector2i.ZERO)
	assert_true(_board.get_cell(Vector2i.ZERO).piece.is_selected)
	_board._on_coordinate_pressed(Vector2i.ZERO)
	assert_null(_board.selected_piece)
	_board._on_coordinate_pressed(Vector2i.ZERO)
	_board._on_coordinate_pressed(Vector2i(8, 8))
	assert_same(_board.selected_piece, _board.get_cell(Vector2i(8, 8)).piece)
	assert_false(_board.get_cell(Vector2i.ZERO).piece.is_selected)
	assert_eq(_board.run.state.action_id, action)
	assert_eq(RunSnapshot.digest(_board.run.state.random_streams.data()), random_before)

func test_preview_uses_canonical_path_and_clears_on_cancel_or_busy() -> void:
	_board._on_coordinate_pressed(Vector2i.ZERO)
	var target: Cell = _board.get_cell(Vector2i(2, 1))
	target._on_mouse_entered()
	await _capture("selection-path")
	var points: PackedVector2Array = _board.view.move_path.get("_points")
	var expected: BoardMoveResult = _board.rules.validate_move(_board.selected_piece.piece_id, target.coordinate)
	assert_eq(points.size(), expected.path.size())
	for index: int in range(points.size()):
		assert_eq(points[index], _board.get_cell(expected.path[index]).position)
	_board.can_selected = false
	assert_eq((_board.view.move_path.get("_points") as PackedVector2Array).size(), 0)
	target._on_mouse_exited()
	target._on_mouse_entered()
	assert_eq((_board.view.move_path.get("_points") as PackedVector2Array).size(), 0)
	_board.can_selected = true
	_board.selected_piece = null
	assert_eq(_board.run.state.action_id, 0)

func test_unreachable_destination_has_no_preview_and_rejection_cancels_selection() -> void:
	_place(Vector2i(1, 0))
	_place(Vector2i(0, 1))
	_board._on_coordinate_pressed(Vector2i.ZERO)
	var target: Cell = _board.get_cell(Vector2i(2, 0))
	target._on_mouse_entered()
	assert_eq((_board.view.move_path.get("_points") as PackedVector2Array).size(), 0)
	await _board._on_coordinate_pressed(target.coordinate)
	assert_null(_board.selected_piece)
	assert_ne(target.background.modulate, Color.WHITE)
	assert_eq(_board.run.state.action_id, 0)
	await wait_seconds(0.2)
	assert_eq(target.background.modulate, Color.WHITE)

func test_hover_material_is_instance_local_and_selected_state_has_priority() -> void:
	var first: ChessPiece = _board.get_cell(Vector2i.ZERO).piece
	var other: ChessPiece = _board.get_cell(Vector2i(8, 8)).piece
	first.set_hovered(true)
	await _capture("piece-hover")
	assert_eq((first.nut_visual.material as ShaderMaterial).get_shader_parameter("hover_amount"), 1.0)
	assert_eq((other.nut_visual.material as ShaderMaterial).get_shader_parameter("hover_amount"), 0.0)
	first.selected()
	assert_eq((first.nut_visual.material as ShaderMaterial).get_shader_parameter("hover_amount"), 0.0)
	first.deselected()
	assert_eq((first.nut_visual.material as ShaderMaterial).get_shader_parameter("hover_amount"), 1.0)

func test_directional_motion_fits_segment_clock_and_cancellation_restores_shape() -> void:
	var piece: ChessPiece = _board.get_cell(Vector2i.ZERO).piece
	var visual: Node2D = piece.get_node("MotionVisuals") as Node2D
	for reduced: bool in [false, true]:
		piece.set_low_effects(reduced)
		piece.move_to_and_wait(_board.get_cell(Vector2i(2, 0)), 0.2)
		piece.tween.pause()
		piece.tween.custom_step(0.05)
		assert_true(visual.scale == Vector2.ONE if reduced else visual.scale.x > visual.scale.y)
		piece.tween.custom_step(0.16)
		assert_eq(visual.scale, Vector2.ONE)
		piece.move_to_and_wait(_board.get_cell(Vector2i(2, 2)), 0.2)
		piece.tween.pause()
		piece.tween.custom_step(0.05)
		assert_true(visual.scale == Vector2.ONE if reduced else visual.scale.y > visual.scale.x)
		piece.cancel_movement()
		assert_eq(visual.scale, Vector2.ONE)

func test_readonly_paths_exclude_occupied_cells_and_do_not_mutate_ids() -> void:
	var piece_id: int = _board.rules.state.get_piece_id(Vector2i.ZERO)
	var before: int = _board.rules.state.get_piece_count()
	var paths: Dictionary[Vector2i, BoardMoveResult] = INTERACTION.selection_paths(_board.rules, piece_id)
	assert_false(paths.has(Vector2i.ZERO))
	assert_false(paths.has(Vector2i(8, 8)))
	assert_true(paths.has(Vector2i(1, 0)))
	assert_eq(_board.rules.state.get_piece_count(), before)
	assert_eq(_board.rules.state.get_piece_id(Vector2i.ZERO), piece_id)

func test_long_path_has_one_clock_in_all_four_modes() -> void:
	for reduced: bool in [false, true]:
		for speed: float in [1.0, 2.0]:
			var rules: BoardRules = BoardRules.new(BoardState.new(9, 9), 5)
			var source: PieceState = rules.place_piece(Vector2i.ZERO, 0)
			for row: int in [1, 3, 5, 7]:
				var opening: int = 8 if row in [1, 5] else 0
				for column: int in range(9):
					if column != opening: rules.place_piece(Vector2i(column, row), 1)
			var view: BoardView = VIEW.instantiate() as BoardView
			add_child_autofree(view)
			view.configure(9, 9, Vector2(64, 64), Vector2.ONE)
			view.set_low_effects(reduced)
			view.presentation_speed = speed
			view.rebuild(rules.state.get_snapshot())
			var result: BoardMoveResult = rules.move_piece(source.piece_id, Vector2i(8, 8))
			assert_gt(result.path.size(), 40)
			var started: int = Time.get_ticks_msec()
			assert_true(await view.animate_move(result, 1.0))
			assert_lt(Time.get_ticks_msec() - started, 500, "Long paths must not wait one frame per cell")
			assert_eq(view.get_cell(Vector2i(8, 8)).piece.piece_id, source.piece_id)
			assert_eq((view.get_piece(source.piece_id).get_node("MotionVisuals") as Node2D).scale, Vector2.ONE)

func test_midmove_pause_low_effects_and_cancel_leave_no_late_deformation() -> void:
	var piece: ChessPiece = _board.get_cell(Vector2i.ZERO).piece
	var result: BoardMoveResult = _board.rules.move_piece(piece.piece_id, Vector2i(6, 0))
	_board.view.animate_move(result, 0.2)
	await wait_process_frames(2)
	get_tree().paused = true
	var stopped: Vector2 = piece.position
	_board.view.set_low_effects(true)
	await wait_process_frames(4)
	assert_eq(piece.position, stopped)
	assert_eq((piece.get_node("MotionVisuals") as Node2D).scale, Vector2.ONE)
	_board.view.cancel_animations()
	get_tree().paused = false
	_board.view.rebuild(_board.rules.state.get_snapshot())
	await wait_seconds(0.3)
	assert_eq(_board.get_cell(Vector2i(6, 0)).piece.piece_id, result.piece_id)
	assert_eq((_board.get_cell(Vector2i(6, 0)).piece.get_node("MotionVisuals") as Node2D).scale, Vector2.ONE)
	assert_eq((_board.view.move_path.get("_points") as PackedVector2Array).size(), 0)

func test_selected_source_removed_clears_selection_and_hover() -> void:
	_board._on_coordinate_pressed(Vector2i.ZERO)
	var piece: ChessPiece = _board.selected_piece
	_board.remove_piece(Vector2i.ZERO, true)
	assert_null(_board.selected_piece)
	assert_false(piece.is_selected)
	assert_false(piece.aura.visible)
	assert_eq((_board.view.move_path.get("_points") as PackedVector2Array).size(), 0)

func _place(coordinate: Vector2i) -> void:
	var piece: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	_board.place_piece(coordinate, piece)

func _capture(label: String) -> void:
	var directory: String = OS.get_environment("O4_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
