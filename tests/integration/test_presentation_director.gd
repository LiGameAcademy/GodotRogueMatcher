extends GutTest

const DIRECTOR: PackedScene = preload("res://gameplay/presentation/presentation_director.tscn")
const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
var director: PresentationDirector
var requests: Array[Dictionary] = []

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	director = DIRECTOR.instantiate() as PresentationDirector
	add_child_autofree(director)
	requests.clear()
	director.step_requested.connect(_capture)

func after_each() -> void:
	get_tree().paused = false
	director.cancel()
	await wait_process_frames(2)

func _capture(step: PresentationStep, epoch: int, token: int) -> void:
	requests.append({"step": step, "epoch": epoch, "token": token})

func _complete(index: int, success: bool = true) -> void:
	var request: Dictionary = requests[index]
	director.complete_step(request.epoch, request.token, success)

func test_queue_requires_matching_completion_and_empty_queue_is_complete() -> void:
	director.enqueue([])
	assert_true(await director.wait_until_idle())
	director.enqueue([PresentationStep.new(), PresentationStep.new()])
	assert_eq(requests.size(), 1)
	_complete(0)
	_complete(0)
	await wait_process_frames(2)
	assert_eq(requests.size(), 2)
	_complete(0)
	assert_true(director.is_busy())
	_complete(1)
	assert_true(await director.wait_until_idle())

func test_cancel_invalidates_old_completion_before_new_queue() -> void:
	director.enqueue([PresentationStep.new()])
	director.cancel()
	director.enqueue([PresentationStep.new()])
	_complete(0)
	assert_true(director.is_busy())
	_complete(1)
	assert_true(await director.wait_until_idle())

func test_paused_completion_does_not_dispatch_next_step() -> void:
	director.enqueue([PresentationStep.new(), PresentationStep.new()])
	get_tree().paused = true
	_complete(0)
	await wait_process_frames(3)
	assert_eq(requests.size(), 1)
	assert_true(director.is_busy())
	get_tree().paused = false
	await wait_process_frames(2)
	assert_eq(requests.size(), 2)
	_complete(1)
	assert_true(await director.wait_until_idle())

func test_failed_action_is_not_successful_completion() -> void:
	watch_signals(director)
	director.enqueue([PresentationStep.new(), PresentationStep.new()])
	_complete(0, false)
	assert_false(await director.wait_until_idle())
	assert_eq(requests.size(), 1)
	assert_signal_emitted_with_parameters(director, "playback_failed", ["presentation_action_failed"])

func test_plan_freezes_path_pieces_and_score_and_orders_generations() -> void:
	var move: BoardMoveResult = BoardMoveResult.new()
	move.path = [Vector2i.ZERO, Vector2i.ONE]
	var frozen: Array[PresentationStep] = PlaybackPlanBuilder.move(move, 0.0)
	move.path.clear()
	assert_eq(frozen[0].movement.path.size(), 2)
	var match_result: MatchResult = MatchResult.new()
	match_result.removed = [PieceState.new()]
	match_result.score_entry = ScoreEntry.new()
	match_result.score_entry.final_score = 50
	var child: MatchResult = MatchResult.new()
	child.generation = 1
	child.score_entry = ScoreEntry.new()
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches([match_result, child])
	match_result.removed[0].match_color = 4
	match_result.score_entry.final_score = 999
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].matches[0].removed[0].match_color, 0)
	assert_eq(steps[0].matches[0].score_entry.final_score, 50)

func test_view_parallel_barrier_waits_for_all_required_tweens() -> void:
	var view: BoardView = VIEW.instantiate() as BoardView
	add_child_autofree(view)
	var short_task: Tween = view.create_tween()
	short_task.tween_interval(0.0)
	var long_task: Tween = view.create_tween()
	long_task.tween_interval(0.1)
	view.track_presentation(short_task)
	view.track_presentation(long_task)
	await wait_process_frames(2)
	assert_true(view.is_presenting())
	assert_true(await view.wait_for_animations())
	assert_false(view.is_presenting())

func test_pausing_freezes_required_visual_tasks() -> void:
	var view: BoardView = VIEW.instantiate() as BoardView
	add_child_autofree(view)
	var animation: Tween = view.create_tween()
	animation.tween_interval(0.1)
	view.track_presentation(animation)
	get_tree().paused = true
	await get_tree().create_timer(0.15).timeout
	assert_true(view.is_presenting())
	get_tree().paused = false
	assert_true(await view.wait_for_animations())

func test_f8_fast_mode_keeps_f6_rule_snapshot_and_telemetry_counts_identical() -> void:
	var main: Node2D = (load("res://main.tscn") as PackedScene).instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	add_child_autofree(main)
	var board: Board = main.get_node("Game/Board") as Board
	await board.initialized
	var baseline: String = ""
	for fast: bool in [false, true]:
		if fast:
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = KEY_F8
			key.pressed = true
			main.get_node("Game").call("_unhandled_key_input", key)
		assert_eq(board.view.presentation_speed, 2.0 if fast else 1.0)
		assert_true(board.load_explosion_demo())
		board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
		assert_true(await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01))
		var digest: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
		if not fast: baseline = digest
		else: assert_eq(digest, baseline)
		var turns: int = 0
		for event: Dictionary in board.observation.telemetry.events:
			if event.event_name == "turn_resolved": turns += 1
		assert_eq(turns, 1)
		assert_eq(GameManager.score, 70)
		assert_eq(board.director.error, "")
		assert_false(board.director.is_busy())
