extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var restart_on_spawn: bool = false
var interrupted_run: RunController
var interrupted_snapshot: Dictionary

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	board = game.get_node("Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child_autofree(game)
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	board.run.state.random.seed = 134
	board.run.state.spawning = SpawnState.new(RunController.SPAWN_CONFIG, 134)
	board.run.prepare_spawn_plan()
	var display: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	assert_true(board.place_piece(Vector2i.ZERO, display))
	board.director.step_requested.connect(_observe_step)

func after_each() -> void:
	restart_on_spawn = false
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(game): game.queue_free()
	await wait_process_frames(3)

func _move() -> bool:
	var piece: PieceState = board.rules.state.get_snapshot()[0]
	for target: Vector2i in board.rules.state.get_empty_coordinates():
		if not board.rules.validate_move(piece.piece_id, target).is_valid(): continue
		board.selected_piece = board.view.get_piece(piece.piece_id)
		return await board.move_selected_piece(board.get_cell(target), 0.01)
	fail_test("夹具应存在合法移动")
	return false

func test_finite_refill_modifier_is_consumed_once_per_actual_batch() -> void:
	board.run.state.spawning.extend_refill(-1, 2)
	for expected: int in [2, 2, 3]:
		var before: int = board.run.state.spawn_history.size()
		var remaining: int = board.run.state.spawning.refill_batches[-1]
		assert_true(await _move())
		assert_eq(board.run.state.spawn_history.size() - before, expected)
		assert_eq(board.run.state.spawning.refill_batches[-1], maxi(0, remaining - 1))
		assert_true(board.can_selected)
	assert_eq(board.run.state.turn_count, 4)

func test_retry_during_birth_cannot_continue_old_run_or_unlock_new_input() -> void:
	restart_on_spawn = true
	_move()
	assert_true(await wait_for_signal(board.initialized, 3.0))
	assert_not_null(interrupted_run)
	assert_ne(board.run, interrupted_run)
	await wait_process_frames(30)
	assert_eq(RunSnapshot.capture(interrupted_run), interrupted_snapshot)
	assert_eq(board.run.state.turn_count, 1)
	assert_eq(board.rules.state.get_piece_count(), RunController.CONFIG.initial_piece_count)
	assert_eq(board.run.state.valid_moves, 0)
	assert_true(board.can_selected)
	assert_false(board.director.is_busy())

func _observe_step(step: PresentationStep, _epoch: int, _token: int) -> void:
	if not restart_on_spawn or step.kind != PresentationStep.Kind.SPAWN: return
	restart_on_spawn = false
	interrupted_run = board.run
	interrupted_snapshot = RunSnapshot.capture(interrupted_run)
	game.call_deferred("_on_retry_requested")
