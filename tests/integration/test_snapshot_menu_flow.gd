extends GutTest

const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const STATE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const GAME: PackedScene = preload("res://gameplay/game.tscn")
var _game: Node
var _directory: String
var _parent: RunCollection

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_directory = "user://snapshot-menu-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(_game):
		(_game.get_node("RunCollection") as RunCollection).suspend_for_checkpoint()
		_game.free()
	if is_instance_valid(_parent):
		_parent.suspend_for_checkpoint()
		_parent.free()
	# Board replacement detaches old cells/pieces and queues them for end-of-frame deletion.
	# Observe that lifecycle before GUT counts the detached subtrees as test-end orphans.
	var pending: PackedInt64Array = PackedInt64Array()
	for id: int in Node.get_orphan_node_ids():
		var node: Node = instance_from_id(id) as Node
		if (node is Cell or node is ChessPiece) and node.get_parent() == null and node.is_queued_for_deletion(): pending.append(id)
	await get_tree().process_frame
	await get_tree().process_frame
	var remaining: int = 0
	for id: int in pending:
		if is_instance_id_valid(id): remaining += 1
	print("CHECKPOINT_TEST_DEFERRED_FREE " + JSON.stringify({"queued_roots": pending.size(), "remaining_after_two_frames": remaining}))
	assert_eq(remaining, 0, "detached board views must finish deferred deletion")
	_remove(_directory)

func _remove(directory: String) -> void:
	assert_true(directory.begins_with("user://snapshot-menu-tests/"))
	for name: String in DirAccess.get_directories_at(directory): _remove(directory.path_join(name))
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func _factory(session_id: String) -> TelemetryFactory:
	var factory: TelemetryFactory = TelemetryFactory.new(session_id)
	factory.directory = _directory.path_join("telemetry")
	factory.record_directory = _directory.path_join("records")
	return factory

func _wait(predicate: Callable) -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	assert_true(bool(predicate.call()), "scene transition completed")

func test_legacy_menu_rejects_explicitly_and_cancel_keeps_original_bytes() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "human", false)
	var slot: String = _directory.path_join("slot")
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(slot), RunCheckpointCodec.manifest(run))
	assert_true(session.save(run).ok)
	var path: String = slot.path_join("primary.json")
	var original: String = FileAccess.get_sha256(path)
	_game = GAME.instantiate()
	_game.set("persist_preferences", false)
	_game.set("record_runs", false)
	_game.set("collect_telemetry", false)
	_game.set("show_start_menu", true)
	_game.set("enable_checkpoints", true)
	_game.set("use_snapshot_checkpoints", true)
	_game.set("checkpoint_directory", slot)
	add_child(_game)
	var menu: ReleaseMenu = _game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	await _wait(func() -> bool: return menu.visible)
	var board: Board = _game.get_node("Board") as Board
	var provisional: RunController = board.run
	var flow: GameCheckpointFlow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	assert_eq(flow.last_error, "legacy_checkpoint_unsupported")
	assert_false(await flow.continue_saved())
	assert_true(flow.prompt.is_open())
	assert_eq(flow.prompt.get("_message"), &"checkpoint.legacy_unsupported")
	flow.prompt.cancel_button.pressed.emit()
	assert_same(board.run, provisional)
	assert_false(bool(_game.get("_has_played")))
	assert_eq(FileAccess.get_sha256(path), original)

func test_snapshot_menu_resume_has_known_native_parent_new_segment_and_ready_input() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	_parent = RunCollection.new()
	_parent.configure("automated_integration", _factory("parent-session"))
	var parent_projector: TelemetryProjector = _parent.factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", true, "scene_resume_test", _parent.factory.record_directory)
	_parent.bind(run)
	_parent.flush()
	var encoded: Dictionary = SNAPSHOT.freeze(run)
	encoded["telemetry"] = await _parent.confirm_snapshot_trace(_parent.snapshot_trace(run, encoded.payload.state_hash))
	var slot: String = _directory.path_join("slot")
	assert_true((await SNAPSHOT.save_frozen(CheckpointStore.new(slot), encoded, encoded.telemetry)).ok)
	_parent.suspend_for_checkpoint()
	var original_path: String = (parent_projector.sink as LocalJsonlSink).path
	var original_hash: String = FileAccess.get_sha256(original_path)
	_game = GAME.instantiate()
	_game.set("persist_preferences", false)
	_game.set("record_runs", true)
	_game.set("collect_telemetry", true)
	_game.set("collection_context", "automated_integration")
	_game.set("show_start_menu", true)
	_game.set("enable_checkpoints", true)
	_game.set("use_snapshot_checkpoints", true)
	_game.set("checkpoint_directory", slot)
	var collection: RunCollection = _game.get_node("RunCollection") as RunCollection
	collection.configure("automated_integration", _factory("provisional-session"))
	add_child(_game)
	var menu: ReleaseMenu = _game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	await _wait(func() -> bool: return menu.visible)
	var board: Board = _game.get_node("Board") as Board
	var provisional: RunController = board.run
	assert_eq(collection.factory.projectors.size(), 0, "saved-slot menu must not emit a new natural run_started")
	menu.play_button.pressed.emit()
	var flow: GameCheckpointFlow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	await _wait(func() -> bool: return board.run != provisional and not flow.restoring and bool(_game.get("_has_played")))
	assert_true(collection.enabled)
	assert_eq(collection.factory.projectors.size(), 1)
	assert_same(board.observation.telemetry, collection.factory.projectors[0])
	var projector: TelemetryProjector = board.observation.telemetry
	assert_eq(projector.events[0].event_name, "run_resumed")
	assert_eq(projector.events[0].run_id, run.state.run_id)
	assert_eq(projector.events[0].segment_id, flow.last_resume_context.prepared.session_id)
	assert_eq(projector.events[0].resume.parent_segment_id, "parent-session")
	assert_eq(projector.observation().ui, "board_input")
	assert_true(FileAccess.file_exists(board.run.recorder.path))
	assert_eq(STATE.project(board.run), STATE.project(run))
	assert_true(projector.events[0].resume.lineage_known)
	assert_eq(board.run.recorder.records[0].kind, "SnapshotHeader")
	assert_true(provisional.recorder == null, "saved-slot menu creates no provisional recorder file")
	var skin: GameTheme = _game.get("game_theme") as GameTheme
	assert_not_null(skin)
	assert_same((_game.get_node("UILayer/HUD") as Hud).theme, skin.ui_theme)
	for piece: ChessPiece in board.view.get("_pieces").values(): assert_same(piece.get("_appearance"), skin.board)
	assert_eq(FileAccess.get_sha256(original_path), original_hash)
	collection.suspend_for_checkpoint()
	var report: TelemetryReport = TelemetryReport.new()
	var reader: TelemetryReader = TelemetryReader.new()
	report.add(reader.read_file(original_path), reader.error)
	report.add(reader.read_file((projector.sink as LocalJsonlSink).path), reader.error)
	assert_eq(report.summary().runs, 1)
	assert_eq(report.errors, [])
