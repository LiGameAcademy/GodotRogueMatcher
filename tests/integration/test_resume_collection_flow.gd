extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var _game: Node
var _directory: String
var _parent: RunCollection

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_directory = "user://resume-scene-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(_game):
		(_game.get_node("RunCollection") as RunCollection).suspend_for_checkpoint()
		_game.free()
	if is_instance_valid(_parent):
		_parent.suspend_for_checkpoint()
		_parent.free()
	_remove(_directory)

func _remove(directory: String) -> void:
	assert_true(directory.begins_with("user://resume-scene-tests/"))
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

func test_actual_menu_resume_has_one_logical_run_no_provisional_start_and_ready_input_observation() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	_parent = RunCollection.new()
	_parent.configure("automated_integration", _factory("parent-session"))
	var parent_projector: TelemetryProjector = _parent.factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", true, "scene_resume_test", _parent.factory.record_directory)
	_parent.bind(run)
	_parent.flush()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = _parent.checkpoint_trace(run)
	var slot: String = _directory.path_join("slot")
	assert_true(RunCheckpointSession.new(CheckpointStore.new(slot), encoded.manifest).save_encoded(encoded).ok)
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
	assert_eq(RunSnapshot.capture(board.run), RunSnapshot.capture(run))
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
