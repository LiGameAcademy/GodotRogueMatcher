extends GutTest

## Checks consumed preview origins, committed identities and birth-clock cleanup.
const RECOVERY: Script = preload("res://tests/support/shape_unlock_fixture.gd")
const MAIN: PackedScene = preload("res://main.tscn")
const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
const PREVIEW: PackedScene = preload("res://ui/spawn_preview.tscn")
var _view: BoardView
var _preview: SpawnPreview
var _capture_done: bool = false
var _births: Array[Dictionary] = []
var _expected_origins: Array[Vector2] = []
var _expected_colors: Array[int] = []

func before_each() -> void:
	_capture_done = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_view = VIEW.instantiate() as BoardView
	add_child_autofree(_view)
	_view.configure(9, 9, Vector2(64, 64), Vector2.ONE)
	_preview = PREVIEW.instantiate() as SpawnPreview
	add_child_autofree(_preview)
	_preview.position = Vector2(250, 10)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_preview_reserves_order_identity_and_does_not_consume_another_slot() -> void:
	var first: SpawnResult = _spawn(11, 2)
	var second: SpawnResult = _spawn(12, 3, &"empty_recovery")
	_preview.show_plan([SpawnToken.new(2, true), SpawnToken.new(3)])
	_preview.prepare_flight([first, second])
	var expected: Vector2 = _preview.get_global_transform_with_canvas() * Vector2(18, 32)
	assert_null(_preview.take_origin(first.piece, 1))
	assert_eq((_preview.take_origin(first.piece, 0) as Transform2D).origin, expected)
	assert_null(_preview.take_origin(first.piece, 0))
	assert_eq((_preview.take_origin(second.piece, 1) as Transform2D).origin, expected + Vector2(36, 0))
	assert_eq((_preview.get("_consumed_slots") as Array[int]).size(), 2)
	# The actual ordinary identity wins over the speculative core marker.
	assert_eq(first.piece.content_id, &"")
	assert_eq(first.piece.match_color, 2)

func test_hud_refresh_does_not_rebind_old_flight_to_the_new_plan() -> void:
	var result: SpawnResult = _spawn(11, 2)
	_preview.show_plan([SpawnToken.new(2)])
	_preview.prepare_flight([result])
	var expected: Vector2 = _preview.get_global_transform_with_canvas() * Vector2(18, 32)
	_preview.position += Vector2(100, 100)
	_preview.show_plan([SpawnToken.new(4)])
	assert_eq((_preview.take_origin(result.piece, 0) as Transform2D).origin, expected)
	assert_eq((_preview.get("_consumed_slots") as Array[int]).size(), 0)

func test_empty_finished_mismatched_and_nonpreview_births_have_no_origin() -> void:
	var result: SpawnResult = _spawn(11, 2)
	_preview.show_plan([])
	_preview.prepare_flight([result])
	assert_null(_preview.take_origin(result.piece, 0))
	_preview.show_plan([SpawnToken.new(2)], true)
	_preview.prepare_flight([result])
	assert_null(_preview.take_origin(result.piece, 0))
	_preview.show_plan([SpawnToken.new(3)])
	_preview.prepare_flight([result])
	assert_null(_preview.take_origin(result.piece, 0))
	_preview.hide()
	_preview.prepare_flight([result])
	assert_null(_preview.take_origin(result.piece, 0))
	_preview.show()
	result.source = &"skill"
	_preview.show_plan([SpawnToken.new(2)])
	_preview.prepare_flight([result])
	assert_null(_preview.take_origin(result.piece, 0))
	assert_eq(PlaybackPlanBuilder.spawns([result], 0.3, true)[0].preview_slot, -1)
	result.source = &"normal"
	assert_eq(PlaybackPlanBuilder.spawns([result], 0.3)[0].preview_slot, -1, "Initial births are not preview consumers")
	assert_eq(PlaybackPlanBuilder.spawns([result], 0.3, true)[0].preview_slot, 0)

func test_flight_uses_existing_birth_clock_and_returns_the_same_node_to_its_cell() -> void:
	var result: SpawnResult = _spawn(11, 2)
	for reduced: bool in [false, true]:
		_view.clear_display()
		_view.scale = Vector2.ONE * 0.65
		_view.set_low_effects(reduced)
		_view.animate_spawn(result.piece, 0.3, Transform2D(0.0, Vector2(250, 42)))
		var piece: ChessPiece = _view.get_piece(11)
		piece.tween.pause()
		assert_eq(piece.piece_type, 2)
		if not reduced: assert_eq(piece.modulate.a, 1.0)
		if reduced: assert_same(_view.get_cell(result.piece.coordinate).piece, piece)
		else: assert_almost_eq(piece.get_global_transform_with_canvas().origin.x, 250.0, 0.01)
		piece.tween.custom_step(0.15)
		assert_true(piece.tween.is_valid())
		piece.tween.custom_step(0.16)
		assert_same(_view.get_cell(result.piece.coordinate).piece, piece)
		assert_eq(_view.get_cell(result.piece.coordinate).background.modulate == Color.WHITE, reduced)
		assert_eq(piece.position, Vector2.ZERO)
		assert_eq(piece.scale, Vector2.ONE)
		assert_eq((piece.get_node("MotionVisuals") as Node2D).scale, Vector2.ONE)

func test_cancel_paused_flight_snaps_and_retry_removes_old_nodes() -> void:
	var result: SpawnResult = _spawn(11, 2)
	_view.animate_spawn(result.piece, 0.3, Transform2D(0.0, Vector2(250, 42)))
	var piece: ChessPiece = _view.get_piece(11)
	await wait_process_frames(2)
	get_tree().paused = true
	var position_before: Vector2 = piece.position
	await wait_process_frames(3)
	assert_eq(piece.position, position_before)
	_view.set_low_effects(true)
	_view.cancel_animations()
	assert_same(_view.get_cell(result.piece.coordinate).piece, piece)
	assert_eq(_view.get_cell(result.piece.coordinate).background.modulate, Color.WHITE)
	assert_eq(piece.position, Vector2.ZERO)
	_view.clear_display()
	get_tree().paused = false
	await wait_seconds(0.35)
	assert_null(_view.get_piece(11))
	assert_eq(_view.get_node("SpawnFlights").get_child_count(), 0)

func test_formal_move_consumes_real_preview_in_four_modes_with_identical_rules() -> void:
	var baseline: String = ""
	for reduced: bool in [false, true]:
		for fast: bool in [false, true]:
			var main: Node2D = MAIN.instantiate() as Node2D
			main.get_node("Game").set("persist_preferences", false)
			var board: Board = main.get_node("Game/Board") as Board
			board.game_mode = GameModes.CLASSIC
			add_child_autofree(main)
			await board.initialized
			var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1212)
			var initial: RunStepResult = run.initialize("normal")
			await board.start_game(run.state.rules, false, run, initial)
			for state: PieceState in board.rules.state.get_snapshot(): board.remove_piece(state.coordinate)
			var source: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
			board.place_piece(Vector2i.ZERO, source)
			var anchor: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
			anchor.piece_type = 1
			board.place_piece(Vector2i(8, 8), anchor)
			board.view.set_low_effects(reduced)
			board.set_playback_fast(fast)
			var hud: Hud = main.get_node("Game/UILayer/HUD") as Hud
			hud.show_run(run)
			_expect(hud.spawn_preview, run.state.spawning.preview(3))
			board.director.step_requested.connect(_observe_birth.bind(board, reduced))
			board.selected_piece = source
			assert_true(await board.move_selected_piece(board.get_cell(Vector2i(1, 0)), 0.12))
			assert_eq(_births.size(), 3, "Formal move must connect the actual visible preview")
			var pieces: Array[Dictionary] = []
			for state: PieceState in board.rules.state.get_snapshot(): pieces.append(RunSnapshot.piece(state))
			var digest: String = RunSnapshot.digest({"pieces": pieces, "rng": run.state.random_streams.data(), "preview": run.state.spawning.plan_data(), "score": run.state.ledger.total})
			if baseline.is_empty(): baseline = digest
			else: assert_eq(digest, baseline)
			assert_eq(board.view.spawn_flight_host.get_child_count(), 0)
			main.queue_free()
			await wait_process_frames(3)

func test_formal_empty_recovery_uses_visible_slots_without_resetting_budget() -> void:
	var main: Node2D = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	var board: Board = main.get_node("Game/Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	await board.initialized
	var run: RunController = RECOVERY.run(true)
	assert_true(RECOVERY.choose(run).accepted)
	await board.start_game(run.state.rules, false, run, RunStepResult.new())
	var hud: Hud = main.get_node("Game/UILayer/HUD") as Hud
	hud.show_run(run)
	_expect(hud.spawn_preview, run.state.spawning.preview(3))
	board.director.step_requested.connect(_observe_birth.bind(board, false))
	await board.resume_run(run)
	assert_eq(_births.size(), 3)
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.valid_moves, 0)
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)
	await board.resume_run(run)
	assert_eq(run.state.spawn_history.size(), 3)

func test_formal_hud_host_pauses_inflight_tween_and_retry_clears_it() -> void:
	var main: Node2D = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	var board: Board = main.get_node("Game/Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	await board.initialized
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1212)
	await board.start_game(run.state.rules, false, run, run.initialize("normal"))
	for state: PieceState in board.rules.state.get_snapshot(): board.remove_piece(state.coordinate)
	var source: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	board.place_piece(Vector2i.ZERO, source)
	var anchor: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	anchor.piece_type = 1
	board.place_piece(Vector2i(8, 8), anchor)
	(main.get_node("Game/UILayer/HUD") as Hud).show_run(run)
	board.director.step_requested.connect(_pause_on_birth)
	board.selected_piece = source
	board.move_selected_piece(board.get_cell(Vector2i(1, 0)), 0.12)
	assert_true(await wait_until(func() -> bool: return get_tree().paused, 3.0))
	var host: Node2D = board.view.spawn_flight_host
	assert_eq(host.get_child_count(), 1)
	var flying: ChessPiece = host.get_child(0) as ChessPiece
	var pose: Transform2D = flying.transform
	await wait_process_frames(6)
	assert_eq(flying.transform, pose, "HUD processes while paused, but flight host must not")
	board.director.step_requested.disconnect(_pause_on_birth)
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	await wait_process_frames(3)
	assert_false(is_instance_valid(flying))
	assert_eq(host.get_child_count(), 0)
	assert_true(board.can_selected)

func _pause_on_birth(step: PresentationStep, _epoch: int, _token: int) -> void:
	if step.kind == PresentationStep.Kind.SPAWN and step.preview_slot >= 0: get_tree().paused = true

func _expect(preview: SpawnPreview, tokens: Array[SpawnToken]) -> void:
	_births.clear()
	_expected_origins.clear()
	_expected_colors.clear()
	for slot: int in range(tokens.size()):
		_expected_origins.append(preview.get_global_transform_with_canvas() * Vector2(18 + slot * 36, 32))
		_expected_colors.append(tokens[slot].color)

func _observe_birth(step: PresentationStep, _epoch: int, _token: int, board: Board, reduced: bool) -> void:
	if step.kind != PresentationStep.Kind.SPAWN or step.preview_slot < 0: return
	var piece: ChessPiece = board.view.get_piece(step.pieces[0].piece_id)
	assert_eq(piece.piece_type, _expected_colors[step.preview_slot])
	if not reduced:
		assert_eq(piece.get_global_transform_with_canvas().origin, _expected_origins[step.preview_slot])
		assert_same(piece.get_parent(), board.view.spawn_flight_host)
	_births.append({"slot": step.preview_slot, "id": piece.piece_id})
	if not reduced: _capture_flight(piece)

func _spawn(id: int, color: int, source: StringName = &"normal") -> SpawnResult:
	var result: SpawnResult = SpawnResult.new()
	result.source = source
	result.piece = PieceState.new()
	result.piece.piece_id = id
	result.piece.match_color = color
	result.piece.coordinate = Vector2i(4, 4)
	return result

func _capture_flight(piece: ChessPiece) -> void:
	var directory: String = OS.get_environment("O4_FLIGHT_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless" or _capture_done: return
	_capture_done = true
	await get_tree().create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	if is_instance_valid(piece):
		get_viewport().get_texture().get_image().save_png(directory.path_join("formal-flight.png"))
