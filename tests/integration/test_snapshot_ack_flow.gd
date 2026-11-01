extends GutTest

## Controlled ACK fixture for frozen parent pointers and the real serial Flow consumer.
## Native adapter tests are not actual browser transaction evidence.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const STATE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
const PERSISTENCE: Script = preload("res://tests/support/web_telemetry_persistence.gd")
const SUPPORT: Script = preload("res://services/telemetry/web_collection_support.gd")
var _game: Node
var _persistence: PERSISTENCE
var _support: SUPPORT
var _flow: GameCheckpointFlow
var _collection: RunCollection
var _directory: String

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if _persistence != null:
		_persistence.hold = false
		_persistence.release_write.emit()
	if _flow != null:
		await _wait(func() -> bool: return _flow.get("_job") == null and not bool(_flow.get("_saving")))
	if is_instance_valid(_game): _game.free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _support != null: await _wait(func() -> bool: return not _support.pending())
	if not _directory.is_empty() and DirAccess.dir_exists_absolute(_directory):
		for name: String in DirAccess.get_files_at(_directory): DirAccess.remove_absolute(_directory.path_join(name))
		DirAccess.remove_absolute(_directory)

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 12000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())

func _start() -> Board:
	_directory = "user://snapshot-ack-tests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_game = GAME.instantiate()
	_game.set("persist_preferences", false)
	_game.set("record_runs", false)
	_game.set("collect_telemetry", false)
	_game.set("show_start_menu", false)
	_game.set("use_snapshot_checkpoints", true)
	_game.set("enable_debug_fixtures", false)
	add_child(_game)
	var board: Board = _game.get_node("Board") as Board
	assert_true(await _wait(func() -> bool: return board.can_selected))
	_persistence = PERSISTENCE.new()
	_support = SUPPORT.new(BACKEND.new(_persistence))
	assert_true((await _support.open()).ok)
	_collection = _game.get_node("RunCollection") as RunCollection
	_collection.set("_web", _support)
	_collection.configure("automated_integration", TelemetryFactory.new("snapshot-ack-parent"), false)
	board.run.recorder = RunRecorder.new()
	var projector: TelemetryProjector = _collection.factory.attach(board.run.recorder, board.run.state.run_id)
	board.run.recorder.begin(board.run, "human", false)
	_collection.bind(board.run)
	board.observation.attach(projector, false)
	assert_true(await _wait(func() -> bool: return not _support.pending()))
	_flow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	_flow.enabled = true
	_flow.set("_store", CheckpointStore.new(_directory))
	return board

func _advance(run: RunController) -> void:
	var bot: GreedyBot = GreedyBot.new(220)
	var command: RunCommand = bot.choose(run)
	assert_not_null(command)
	if command == null: return
	assert_true(run.execute_command(command).accepted)
	for index: int in range(40):
		if run.state.phase == RunState.Phase.INPUT or run.state.rewards.active_offer != null: return
		run.advance()

func test_held_parent_ack_then_new_action_coalesces_latest_snapshot_and_pins_its_original_row() -> void:
	var board: Board = await _start()
	_persistence.hold = true
	_flow.arm_current()
	assert_true(await _wait(func() -> bool: return _persistence.writing))
	assert_true(bool(_flow.get("_saving")))
	assert_null(_flow.get("_job"), "rule write cannot start before the pending parent decision")
	var first_hash: String = RunSnapshot.digest(STATE.project(board.run))
	_advance(board.run)
	_flow.call("_on_safe_point", board.run)
	var queued: Dictionary = _flow.get("_queued")
	assert_false(queued.is_empty())
	assert_ne(queued.payload.state_hash, first_hash)
	var expected_parent: String = queued.telemetry.last_event_id
	var expected_hash: String = queued.payload.state_hash
	assert_true(_support.snapshot_parent(queued.telemetry).is_empty(), "accepted row is not in ACK view")
	_persistence.hold = false
	_persistence.release_write.emit()
	assert_true(await _wait(func() -> bool: return not bool(_flow.get("_saving")) and _flow.get("_job") == null))
	var loaded: Dictionary = SNAPSHOT.load(CheckpointStore.new(_directory), SNAPSHOT.manifest(board.run))
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	assert_eq(loaded.resume_context.state_hash, expected_hash)
	assert_eq(loaded.trace.last_event_id, expected_parent)
	assert_eq(loaded.trace.persisted_seq, loaded.trace.accepted_seq)
	assert_false(_support.snapshot_parent(loaded.trace).is_empty())
	assert_eq(STATE.project(loaded.run), STATE.project(board.run))

func test_cancel_and_epoch_change_while_waiting_ack_cannot_publish_or_write_old_snapshot() -> void:
	var board: Board = await _start()
	_persistence.hold = true
	_flow.arm_current()
	assert_true(await _wait(func() -> bool: return _persistence.writing))
	_flow.request_exit("test-cancel")
	_flow.prompt.cancel_button.pressed.emit()
	assert_false(_flow.closing)
	_flow.call("_on_run_reset")
	_persistence.hold = false
	_persistence.release_write.emit()
	assert_true(await _wait(func() -> bool: return not bool(_flow.get("_saving")) and not bool(_flow.get("_exit_saving"))))
	assert_false(_flow.saved_available)
	assert_false(CheckpointStore.new(_directory).inspect_latest().ok)
	assert_true(board.run.recorder != null)

func test_failed_parent_ack_keeps_rule_checkpoint_usable_with_unknown_lineage() -> void:
	var board: Board = await _start()
	_persistence.fail_write = true
	_flow.arm_current()
	assert_true(await _wait(func() -> bool: return not bool(_flow.get("_saving")) and _flow.get("_job") == null))
	var loaded: Dictionary = SNAPSHOT.load(CheckpointStore.new(_directory), SNAPSHOT.manifest(board.run))
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok:
		assert_eq(loaded.trace, {})
		assert_eq(STATE.project(loaded.run), STATE.project(board.run))