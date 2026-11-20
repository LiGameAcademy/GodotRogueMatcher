extends SceneTree

## Exercises the actual application in isolated user data, across host-controlled processes.
const PAUSING_FILES: Script = preload("res://tools/checkpoint_benchmark/process_checkpoint_files.gd")
const TAIL_SINK: Script = preload("res://tools/checkpoint_benchmark/process_tail_sink.gd")
const FLOAT_TRANSPORT: Script = preload("res://services/run_checkpoint/checkpoint_float_transport.gd")
var _case: String
var _mode: String
var _phase: String
var _point: String = "input"
var _base: String
var _output: String
var _game: Node
var _board: Node
var _flow: Node
var _collection: RunCollection
var _fault_armed: bool = false
var _report: Dictionary = {"kind": "instrumented_native_process", "author_feedback": null}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() not in [3, 4]: return _fail("expected_case_mode_phase_point")
	_case = args[0]
	_mode = args[1]
	_phase = args[2]
	if args.size() == 4: _point = args[3]
	var valid: RegEx = RegEx.create_from_string("^[a-zA-Z0-9_-]+$")
	if valid.search(_case) == null: return _fail("invalid_case")
	if _mode not in ["normal", "kill", "restore"] or _phase not in ["none", "partial", "backup", "primary"]: return _fail("invalid_mode")
	if _point not in ["input", "reward"]: return _fail("invalid_point")
	_base = "user://process-checkpoint-probe/" + _case
	_output = "res://.godot/" + _case
	create_timer(240.0).timeout.connect(func() -> void: _fail("probe_watchdog_timeout"), CONNECT_ONE_SHOT)
	_report.merge({"pid": OS.get_process_id(), "case": _case, "mode": _mode, "phase": _phase, "point": _point})
	if DisplayServer.get_name() == "headless": return _fail("gpu_required")
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	_game = main.get_node("Game")
	_board = _game.get_node("Board")
	_board.game_mode = GameModes.CLASSIC
	_game.set("checkpoint_directory", _base.path_join("slot"))
	_game.set("persist_preferences", false)
	_collection = _game.get_node("RunCollection") as RunCollection
	var factory: TelemetryFactory = TelemetryFactory.new()
	factory.directory = _base.path_join("telemetry")
	factory.record_directory = _base.path_join("records")
	var telemetry_directory: String = factory.directory
	factory.sink_factory = func(id: String) -> TelemetrySink: return TAIL_SINK.new(id, telemetry_directory)
	_collection.configure("automated_integration", factory)
	root.add_child(main)
	_game.set("collection_context", "automated_integration")
	_game.call("_set_fast", true, false)
	_flow = _game.get_node("GameCheckpointFlow")
	var menu: Node = _game.get_node("MenuLayer/ReleaseMenu")
	if not await _wait(func() -> bool: return menu.visible): return _fail("menu_timeout")
	var receipt: Dictionary = {}
	if _mode == "restore":
		var transported: Dictionary = FLOAT_TRANSPORT.decode(JSON.parse_string(FileAccess.get_file_as_string(_output + "-receipt.json")))
		if not transported.ok: return _fail("receipt_transport_invalid")
		receipt = transported.data
		_report["pair_before_play_equal"] = _pair() == receipt.pair
		if not _report.pair_before_play_equal: return _fail("recovered_pair_mismatch")
	menu.play_button.pressed.emit()
	if not await _wait(func() -> bool: return bool(_game.get("_has_played")) and not bool(_flow.get("restoring"))): return _fail("start_timeout")
	if _mode == "restore":
		await _restore(receipt)
		return
	if not await _wait(_stable): return _fail("initial_save_timeout")
	if _point == "reward":
		if not await _seek_reward(): return _fail("no_reachable_frozen_reward")
	elif not await _move(): return _fail("first_move_failed")
	if not await _wait(_stable): return _fail("first_save_timeout")
	var prediction: Dictionary = _prediction()
	if prediction.is_empty(): return _fail("no_safe_next_move")
	receipt = {"pair": _pair(), "snapshot": RunSnapshot.capture(_board.run), "next": prediction,
		"run_id": _board.run.state.run_id, "user_directory": OS.get_user_data_dir(),
		"telemetry_path": (_board.observation.telemetry.sink as LocalJsonlSink).path}
	_write("-receipt.json", FLOAT_TRANSPORT.encode(receipt).data)
	if _mode == "normal":
		_close()
		return
	var files: CheckpointFiles = PAUSING_FILES.new()
	files.set("phase", _phase)
	files.set("signal_path", _output + "-phase.json")
	_flow.set("_store", CheckpointStore.new(_base.path_join("slot"), files))
	_fault_armed = true
	create_timer(180.0).timeout.connect(func() -> void: _fail("host_kill_watchdog_timeout"), CONNECT_ONE_SHOT)
	if not await _move(prediction): return _fail("fault_move_failed")
	if not await _wait(func() -> bool: return FileAccess.file_exists(_output + "-phase.json")): return _fail("phase_timeout")
	_collection.flush()
	var sink: LocalJsonlSink = _board.observation.telemetry.sink as LocalJsonlSink
	if not bool(sink.call("inject_unknown_tail")): return _fail("tail_injection_failed")
	_write("-ready.json", {"pid": OS.get_process_id(), "phase": _phase,
		"original_path": sink.path, "original_hash": FileAccess.get_sha256(sink.path)})
	# Host performs a real forced termination. A normal quit would block joining the paused worker.
	await process_frame

func _restore(receipt: Dictionary) -> void:
	_report["snapshot_equal"] = RunSnapshot.capture(_board.run) == receipt.snapshot
	_report["same_run"] = _board.run.state.run_id == receipt.run_id
	_report["resume_context"] = _flow.last_resume_context.duplicate(true)
	var ready_path: String = _output + "-ready.json"
	if FileAccess.file_exists(ready_path):
		var ready: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ready_path))
		_report["unknown_tail_unchanged"] = FileAccess.get_sha256(ready.original_path) == ready.original_hash
		var reader: TelemetryReader = TelemetryReader.new()
		reader.read_file(ready.original_path)
		_report["parent_reader_error"] = reader.error
		if not _report.unknown_tail_unchanged or not "incomplete_last_line" in str(reader.error): return _fail("unknown_tail_not_preserved")
	if not _report.snapshot_equal or not _report.same_run:
		_report["actual_snapshot"] = RunSnapshot.capture(_board.run)
		return _fail("restore_state_mismatch")
	if not await _move(receipt.next): return _fail("restored_move_failed")
	_report["next_snapshot_equal"] = RunSnapshot.capture(_board.run) == receipt.next.state
	if not _report.next_snapshot_equal: return _fail("next_state_mismatch")
	if not await _wait(_stable): return _fail("restored_save_timeout")
	_collection.flush()
	var reader: TelemetryReader = TelemetryReader.new()
	var events: Array[Dictionary] = reader.read_file(receipt.telemetry_path)
	var parent_error: String = reader.error
	var child_path: String = (_board.observation.telemetry.sink as LocalJsonlSink).path
	events.append_array(reader.read_file(child_path))
	var expected_parent_error: String = "incomplete_last_line" if FileAccess.file_exists(ready_path) else "incomplete_telemetry_no_complete_ending"
	if parent_error != expected_parent_error or reader.error != "incomplete_telemetry_no_complete_ending": return _fail("unexpected_telemetry_read_error")
	var lineage: Dictionary = TelemetryLineage.normalize(events)
	_report["lineage"] = {"errors": lineage.errors, "branches": lineage.branches,
		"streams": lineage.streams.size(), "parent_read_error": parent_error, "child_read_error": reader.error}
	if not lineage.errors.is_empty() or lineage.streams.size() != 1: return _fail("lineage_not_unique")
	var starts: int = 0
	var endings: int = 0
	for event: Dictionary in lineage.streams[0]:
		if event.event_name == "run_started": starts += 1
		if event.event_name == "run_ended": endings += 1
	_report["natural_starts"] = starts
	_report["natural_endings"] = endings
	if starts != 1 or endings != 0: return _fail("synthetic_natural_run")
	_close()

func _prediction() -> Dictionary:
	var encoded: Dictionary = RunCheckpointCodec.encode(_board.run)
	if not encoded.ok: return {}
	var commands: Array[RunCommand] = []
	if _board.run.state.phase == RunState.Phase.REWARDS:
		commands.append(GreedyBot.new().choose(_board.run))
	else: commands.append_array(RuleBot.new().legal_moves(_board.run))
	for command: RunCommand in commands:
		var decoded: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest, 10000000)
		if not decoded.ok: return {}
		var candidate: RunController = decoded.run
		command.source = "human"
		command.buffered_wait_ms = 0
		candidate.execute_command(command)
		for step: int in range(40):
			if RunCheckpointCodec.safety_error(candidate).is_empty(): break
			if candidate.state.is_game_over: break
			candidate.advance()
		if RunCheckpointCodec.safety_error(candidate).is_empty():
			return {"command": CommandCodec.encode(command), "state": RunSnapshot.capture(candidate)}
	return {}

func _move(prediction: Dictionary = {}) -> bool:
	var chosen: Dictionary = _prediction() if prediction.is_empty() else prediction
	if chosen.is_empty(): return false
	var command: RunCommand = CommandCodec.decode(chosen.command)
	if command is ChooseSkillCommand:
		var choice: ChooseSkillCommand = command as ChooseSkillCommand
		var manager: Node = root.get_node("UIManager")
		if not await _wait(func() -> bool:
			var current: Node = manager.get("current_popup")
			return current != null and current.has_signal("color_skill_selected") and not current.get_signal_connection_list("color_skill_selected").is_empty()): return false
		var popup: Node = manager.get("current_popup")
		var before: int = _board.run.last_command_id
		popup.emit_signal("color_skill_selected", choice.offer_id, choice.skill_id, choice.selected_color)
		if not await _wait(func() -> bool: return _board.run.last_command_id > before and RunCheckpointCodec.safety_error(_board.run).is_empty()): return false
		return true
	var move: MovePieceCommand = command as MovePieceCommand
	_board.selected_piece = _board.view.get_piece(move.piece_id)
	return await _board.move_selected_piece(_board.get_cell(move.target), 0.01, 0)

func _seek_reward() -> bool:
	for action: int in range(120):
		if _board.run.state.phase == RunState.Phase.REWARDS: return true
		if _board.run.state.is_game_over or not _board.can_selected: return false
		var command: MovePieceCommand = GreedyBot.new().choose(_board.run) as MovePieceCommand
		if command == null: return false
		_board.selected_piece = _board.view.get_piece(command.piece_id)
		if not await _board.move_selected_piece(_board.get_cell(command.target), 0.01, 0): return false
		if not await _wait(_stable): return false
	return false

func _stable() -> bool:
	return bool(_game.get("_has_played")) and RunCheckpointCodec.safety_error(_board.run).is_empty() and not _flow.is_busy() and _flow.get("_job") == null and not bool(_flow.get("_saving")) and String(_flow.get("_last_key")) == _board.run.state.run_id + ":" + str(_board.run.recorder.records.size())

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 30000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await process_frame
	return bool(predicate.call())

func _pair() -> Dictionary:
	var directory: String = _base.path_join("slot")
	return {"primary": FileAccess.get_sha256(directory.path_join("primary.json")), "previous": FileAccess.get_sha256(directory.path_join("previous.json"))}

func _close() -> void:
	_flow.exit_ready.connect(func(reason: String) -> void:
		_report["normal_exit_signal"] = reason
		if _mode == "restore":
			var reader: TelemetryReader = TelemetryReader.new()
			reader.read_file((_board.observation.telemetry.sink as LocalJsonlSink).path)
			_report["closed_child_error"] = reader.error
			_report["closed_child_segment_complete"] = reader.segment_complete
			if not reader.error.is_empty() or not reader.segment_complete:
				_report["error"] = "child_segment_not_closed"
				quit(1)
		_write("-" + _mode + "-report.json", _report), CONNECT_ONE_SHOT)
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _write(suffix: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output + suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	print("NATIVE_PROCESS " + suffix)

func _fail(reason: String) -> void:
	_report["error"] = reason
	if not _output.is_empty(): _write("-" + _mode + "-report.json", _report)
	push_error(reason)
	if _fault_armed:
		OS.kill(OS.get_process_id())
		return
	quit(1)
