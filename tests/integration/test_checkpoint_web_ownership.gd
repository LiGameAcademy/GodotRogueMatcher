extends GutTest

## A held browser invalidation must keep application ownership after cancelling its UI.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const FILES: Script = preload("res://services/run_checkpoint/checkpoint_web_files.gd")
const BACKEND: Script = preload("res://tests/support/checkpoint_web_backend.gd")
var _game: Node

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(_game): _game.free()
	await get_tree().process_frame
	await get_tree().process_frame

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())

func test_cancelled_terminal_exit_cannot_start_or_load_until_invalidation_acknowledged() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_test", false, "web_ownership_test")
	var backend: BACKEND = BACKEND.new()
	var files: FILES = FILES.new("user://web-ownership-slot", backend)
	await files.open()
	var store: CheckpointStore = CheckpointStore.new("user://web-ownership-slot", files)
	assert_true(RunCheckpointSession.new(store, RunCheckpointCodec.manifest(run)).save(run).ok)
	assert_true((await store.sync()).ok)
	var original: String = backend.image
	var bot: GreedyBot = GreedyBot.new(7)
	for step: int in range(1000):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): break
		if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
			run.advance()
		elif run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
			var command: RunCommand = bot.choose(run)
			if command == null: break
			run.execute_command(command)
		else: run.advance()
	assert_true(run.state.is_game_over, "real rules must reach a natural terminal state")
	_game = GAME.instantiate()
	_game.set("persist_preferences", false)
	_game.set("record_runs", false)
	_game.set("collect_telemetry", false)
	_game.set("show_start_menu", true)
	_game.set("enable_checkpoints", false)
	add_child(_game)
	assert_true(await _wait(func() -> bool: return (_game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu).visible))
	get_tree().paused = false
	var board: Board = _game.get_node("Board") as Board
	await board.start_game(run.state.rules, false, run, RunStepResult.new())
	assert_true(board.run.state.is_game_over, "install already-completed rules without reinitializing them")
	var flow: GameCheckpointFlow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	flow.enabled = true
	flow.set("_store", store)
	flow.set("_armed", true)
	flow.exit_ready.disconnect(Callable(_game, "_finish_quit"))
	backend.hold = true
	backend.fail_write = true
	flow.request_exit("web_terminal_close")
	assert_true(await _wait(func() -> bool: return backend.writing))
	assert_null(flow.get("_job"), "this wait is an invalidation acknowledgement, not a worker")
	flow.prompt.cancel_button.pressed.emit()
	assert_false(flow.closing)
	assert_true(flow.is_busy(), "cancelling UI must retain the pending invalidation owner")
	var permissions: Array[bool] = []
	var request: Callable = func() -> void: permissions.append(await flow.allow_new_run())
	request.call()
	await get_tree().process_frame
	if permissions.is_empty() and flow.prompt.is_open(): flow.prompt.primary.pressed.emit()
	assert_true(await _wait(func() -> bool: return not permissions.is_empty()))
	if not permissions.is_empty(): assert_false(permissions[0], "new-run permission cannot use an unacknowledged in-memory marker")
	assert_false(await flow.continue_saved())
	assert_eq(flow.last_error, "worker_busy")
	backend.release_write.emit()
	assert_true(await _wait(func() -> bool: return not bool(flow.get("_exit_saving"))))
	assert_eq(backend.image, original, "failed persistence retains the old durable identity")
	var reopened: FILES = FILES.new("user://web-ownership-slot", backend)
	await reopened.open()
	assert_true(CheckpointStore.new("user://web-ownership-slot", reopened).inspect_latest().ok)
