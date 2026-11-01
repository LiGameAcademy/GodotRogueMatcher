extends "res://tools/checkpoint_benchmark/snapshot_menu_probe.gd"

## Isolated real-browser failure consumer. Aborts real checkpoint transactions;
## a withheld telemetry completion tests cancel/reload before the parent ACK is observed.
const FAULTS: String = "res://tools/checkpoint_benchmark/snapshot_fault_probe.js"
var _measuring: bool = false
var _measure_started: int = 0
var _last_frame: int = 0
var _maximum_frame: int = 0
var _memory_before: int = 0
var _memory_peak: int = 0

func _process(delta: float) -> void:
	super._process(delta)
	if _measuring:
		var now: int = Time.get_ticks_usec()
		_maximum_frame = maxi(_maximum_frame, now - _last_frame)
		_last_frame = now
		_memory_peak = maxi(_memory_peak, int(Performance.get_monitor(Performance.MEMORY_STATIC)))

func _run() -> void:
	if not OS.has_feature("web") or str(JavaScriptBridge.eval("location.origin", true)) != "http://127.0.0.1:8994":
		_finish(false, "fault_probe_origin_rejected")
		return
	JavaScriptBridge.eval(FileAccess.get_file_as_string(FAULTS), true)
	var files: FILES = FILES.new("user://snapshot-fault-probe")
	if not (await files.open()).ok:
		_finish(false, "open_failed")
		return
	var store: CheckpointStore = CheckpointStore.new("user://snapshot-fault-probe", files)
	var prior: Dictionary = store.inspect_latest()
	seed(899023)
	_game = GAME.instantiate()
	for key: String in ["persist_preferences", "record_runs", "enable_debug_fixtures"]: _game.set(key, false)
	_game.set("collect_telemetry", true)
	_game.set("collection_context", "automated_integration")
	_game.set("show_start_menu", true)
	_game.set("enable_checkpoints", true)
	_game.set("use_snapshot_checkpoints", true)
	_game.set("checkpoint_directory", "user://snapshot-fault-probe")
	(_game.get_node("Board") as Board).game_mode = GameModes.find(&"stage_challenge")
	add_child(_game)
	_board = _game.get_node("Board") as Board
	_flow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	_collection = _game.get_node("RunCollection") as RunCollection
	var menu: ReleaseMenu = _game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	if not await _wait(func() -> bool: return menu.visible):
		_finish(false, "menu_timeout")
		return
	_details = {"origin": "http://127.0.0.1:8994", "mode": "stage_challenge", "real_transaction_abort": true}
	if prior.ok:
		var reference: Dictionary = SNAPSHOT.load(store, prior.manifest)
		var provisional: RunController = _board.run
		_measure_started = Time.get_ticks_usec()
		_last_frame = _measure_started
		_memory_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		_memory_peak = _memory_before
		_measuring = true
		menu.play_button.pressed.emit()
		if not await _wait(func() -> bool: return _board.run != provisional and not _flow.restoring):
			_finish(false, "refresh_resume_failed")
			return
		await get_tree().process_frame
		_measuring = false
		_details["restore_window"] = {"elapsed_usec": Time.get_ticks_usec() - _measure_started, "maximum_process_frame_gap_usec": _maximum_frame, "static_memory_before_bytes": _memory_before, "static_memory_peak_bytes": _memory_peak, "job": _flow.last_job_metrics}
		_details["phase"] = "refresh_after_withheld_parent_ack"
		_details["confirmed_point_restored"] = reference.ok and STATE.project(reference.run) == STATE.project(_board.run)
		_details["confirmed_hash"] = reference.resume_context.state_hash
		if str(JavaScriptBridge.eval("location.search", true)) == "?pending=1":
			if not await _wait(_choice_ready):
				_finish(false, "pending_refresh_choice_missing")
				return
			JavaScriptBridge.eval("window.snapshotFault.holdTelemetryAck=true", true)
			_emit_choice(UIManager.current_popup as PopupSkillChoice, _bot.choose(_board.run) as ChooseSkillCommand)
			if not await _wait(func() -> bool: return int(JavaScriptBridge.eval("window.snapshotFault.held", true)) > 0 and bool(_flow.get("_saving")) and _flow.get("_job") == null):
				_finish(false, "pending_refresh_no_parent_wait")
				return
			print("PENDING_REFRESH_READY " + JSON.stringify({"state_hash": reference.resume_context.state_hash, "no_checkpoint_job": _flow.get("_job") == null, "saving": _flow.get("_saving"), "telemetry_commit_ack_dropped": true}))
			return
		_finish(_details.confirmed_point_restored, "")
		return
	if prior.reason != "no_valid_checkpoint:missing":
		_finish(false, "refuse_existing_slot:" + prior.reason)
		return
	menu.play_button.pressed.emit()
	if not await _wait(func() -> bool: return bool(_game.get("_has_played"))):
		_finish(false, "start_failed")
		return
	if not await _drive(true) or not await _wait(_saved_idle):
		_finish(false, "baseline_not_saved")
		return
	var baseline: Dictionary = await _read_durable()
	if not baseline.ok:
		_finish(false, "baseline_read_failed")
		return
	var hash: String = baseline.resume_context.state_hash
	JavaScriptBridge.eval("window.snapshotFault.abortCheckpoint=true", true)
	_emit_choice(UIManager.current_popup as PopupSkillChoice, _bot.choose(_board.run) as ChooseSkillCommand)
	if not await _wait(func() -> bool: return not _flow.last_error.is_empty() and not bool(_flow.get("_saving"))):
		_finish(false, "rejected_save_not_reported")
		return
	var rejected: Dictionary = await _read_durable()
	_details["save_failure_visible"] = _flow.last_error.ends_with("web_storage_write_failed")
	_details["save_failure_preserves_confirmed"] = rejected.ok and rejected.resume_context.state_hash == hash
	var active: RunController = _board.run
	_try_new_run()
	if not await _wait(func() -> bool: return _flow.prompt.is_open()):
		_finish(false, "new_run_confirmation_missing")
		return
	_flow.prompt.primary.pressed.emit()
	if not await _wait(func() -> bool: return _flow.prompt.get("_kind") == &"invalidate_failed"):
		_finish(false, "new_run_invalidation_failure_missing")
		return
	_flow.prompt.cancel_button.pressed.emit()
	if not await _wait(func() -> bool: return _details.has("new_run_allowed")):
		_finish(false, "new_run_did_not_settle")
		return
	_details["new_run_blocked"] = not _details.new_run_allowed and _board.run == active
	JavaScriptBridge.eval("window.snapshotFault.abortCheckpoint=false;window.snapshotFault.holdTelemetryAck=true", true)
	_flow.set("_last_key", "")
	_flow.arm_current()
	if not await _wait(func() -> bool: return int(JavaScriptBridge.eval("window.snapshotFault.held", true)) > 0):
		_finish(false, "parent_ack_not_withheld")
		return
	_details["parent_wait_has_no_checkpoint_job"] = bool(_flow.get("_saving")) and _flow.get("_job") == null
	_flow.request_exit("agent_cancel_pending_parent")
	_flow.prompt.cancel_button.pressed.emit()
	_flow.call("_on_run_reset")
	if not await _wait(func() -> bool: return not bool(_flow.get("_saving")) and not bool(_flow.get("_exit_saving"))):
		_finish(false, "cancel_pending_parent_did_not_settle")
		return
	var cancelled: Dictionary = await _read_durable()
	_details["cancel_preserves_confirmed"] = cancelled.ok and cancelled.resume_context.state_hash == hash
	JavaScriptBridge.eval("window.snapshotFault.abortCheckpoint=true", true)
	if not await _drive(false): return
	if not await _wait(func() -> bool: return _flow.prompt.get("_kind") == &"terminal_failed"):
		_finish(false, "terminal_failure_not_visible")
		return
	var terminal: Dictionary = await _read_durable()
	_details["terminal_not_claimed_durable"] = _flow.last_error.ends_with("web_storage_write_failed") and terminal.ok and terminal.resume_context.state_hash == hash
	_details["aborted_transactions"] = int(JavaScriptBridge.eval("window.snapshotFault.aborted", true))
	_details["phase"] = "failed_save_invalidation_and_cancel_before_refresh"
	_finish(_details.save_failure_visible and _details.save_failure_preserves_confirmed and _details.new_run_blocked and _details.parent_wait_has_no_checkpoint_job and _details.cancel_preserves_confirmed and _details.terminal_not_claimed_durable, "")

func _try_new_run() -> void:
	_details["new_run_allowed"] = await _flow.allow_new_run()

func _read_durable() -> Dictionary:
	var files: FILES = FILES.new("user://snapshot-fault-probe")
	var opened: Dictionary = await files.open()
	if not opened.ok: return opened
	return SNAPSHOT.load(CheckpointStore.new("user://snapshot-fault-probe", files), SNAPSHOT.manifest(_board.run))
