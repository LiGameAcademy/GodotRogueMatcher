extends GutTest

const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
var view: BoardView
var run: RunController

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 37)
	run.initialize()
	view = VIEW.instantiate() as BoardView
	add_child_autofree(view)
	view.configure(9, 9, Vector2(64, 64), Vector2.ONE)
	view.rebuild(run.state.rules.state.get_snapshot())

func after_each() -> void:
	get_tree().paused = false
	await wait_process_frames(2)

func _first_piece() -> ChessPiece:
	return view.get_piece(run.state.rules.state.get_snapshot()[0].piece_id)

func _accelerate(piece: ChessPiece) -> void:
	var config: NutIdleConfig = piece.nut_visual.idle_config.duplicate() as NutIdleConfig
	config.first_blink_range = Vector2(0.03, 0.04)
	config.blink_interval_range = Vector2(0.04, 0.05)
	config.closed_seconds = 0.08
	piece.nut_visual.configure_idle(piece.piece_id, false)
	piece.nut_visual.idle_config = config
	piece.nut_visual.configure_idle(piece.piece_id, true)

func test_stagger_and_refresh_preserve_timer_and_gameplay_random_streams() -> void:
	var snapshot: Array[PieceState] = run.state.rules.state.get_snapshot()
	var a: ChessPiece = view.get_piece(snapshot[0].piece_id)
	var b: ChessPiece = view.get_piece(snapshot[1].piece_id)
	assert_ne(a.nut_visual.blink_timer.wait_time, b.nut_visual.blink_timer.wait_time)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var cosmetic_state: int = a.nut_visual.get("_cosmetic_random").state
	var wait_time: float = a.nut_visual.blink_timer.time_left
	a.apply_game_theme(GameThemes.ALL[1].board)
	assert_eq(a.nut_visual.get("_cosmetic_random").state, cosmetic_state)
	assert_eq(a.nut_visual.blink_timer.time_left, wait_time)
	for index: int in range(20): a.nut_visual.blink_timer.timeout.emit()
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(b.nut_visual.idle_config.closed_seconds, 0.14)

func test_real_timer_closes_then_opens_and_pause_freezes_closed_pose() -> void:
	var piece: ChessPiece = _first_piece()
	_accelerate(piece)
	await piece.nut_visual.blink_timer.timeout
	assert_true(piece.nut_visual.eyes_closed)
	get_tree().paused = true
	var remaining: float = piece.nut_visual.blink_timer.time_left
	await wait_process_frames(8)
	assert_true(piece.nut_visual.eyes_closed)
	assert_eq(piece.nut_visual.blink_timer.time_left, remaining)
	get_tree().paused = false
	await piece.nut_visual.blink_timer.timeout
	assert_false(piece.nut_visual.eyes_closed)
	assert_gt(piece.nut_visual.blink_timer.time_left, 0.0)

func test_low_effects_and_selection_interrupt_and_restore_idle() -> void:
	var piece: ChessPiece = _first_piece()
	_accelerate(piece)
	await piece.nut_visual.blink_timer.timeout
	assert_true(piece.nut_visual.eyes_closed)
	view.set_low_effects(true)
	assert_false(piece.nut_visual.eyes_closed)
	assert_true(piece.nut_visual.blink_timer.is_stopped())
	await wait_process_frames(8)
	assert_false(piece.nut_visual.eyes_closed)
	view.set_low_effects(false)
	await piece.nut_visual.blink_timer.timeout
	piece.selected()
	assert_false(piece.nut_visual.eyes_closed)
	assert_true(piece.nut_visual.blink_timer.is_stopped())
	piece.deselected()
	assert_false(piece.nut_visual.blink_timer.is_stopped())

func test_move_and_elimination_interrupt_without_waiting_for_blink() -> void:
	var piece: ChessPiece = _first_piece()
	_accelerate(piece)
	await piece.nut_visual.blink_timer.timeout
	var source: Vector2i = run.state.rules.state.get_piece(piece.piece_id).coordinate
	var target: Vector2i = Vector2i(source.x, posmod(source.y + 1, 9))
	while run.state.rules.state.get_piece_at(target) != null: target.y = posmod(target.y + 1, 9)
	var result: BoardMoveResult = run.state.rules.move_piece(piece.piece_id, target)
	assert_true(result.is_valid())
	view.animate_move(result, 0.1)
	assert_false(piece.nut_visual.eyes_closed)
	assert_true(piece.nut_visual.blink_timer.is_stopped())
	assert_true(await view.wait_for_animations())
	assert_false(piece.nut_visual.blink_timer.is_stopped())
	piece.eliminate()
	assert_false(piece.nut_visual.eyes_closed)
	assert_true(piece.nut_visual.blink_timer.is_stopped())
	assert_eq(run.state.rules.state.get_piece(piece.piece_id).coordinate, target)
