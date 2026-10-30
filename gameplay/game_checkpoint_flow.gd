class_name GameCheckpointFlow
extends Node

## Application owner of one serial checkpoint job and its explicit exit policy.
## Rules stay in RunController; the scene parent owns sibling HUD/reward/collection wiring.
signal status_changed(message_id: StringName)
signal before_restore
signal restored(active: RunController, fallback: bool)
signal settling_exit
signal exit_ready(reason: String)
signal operation_cancelled

const DESKTOP_BUDGET_USEC: int = 10000000
const WEB_FILES: Script = preload("res://services/run_checkpoint/checkpoint_web_files.gd")
var enabled: bool = false
var saved_available: bool = false
var saved_mode: StringName = &"stage_challenge"
var last_error: String = ""
var restoring: bool = false
var closing: bool = false
var last_freeze_usec: int = 0
var last_job_metrics: Dictionary = {}
var trace_provider: Callable
var resume_plan_provider: Callable
var last_resume_context: Dictionary = {}
var _board: Board
var _store: CheckpointStore
var _job: CheckpointJob
var _armed: bool = false
var _saving: bool = false
var _transition: bool = false
var _exit_saving: bool = false
var _queued: Dictionary = {}
var _epoch: int = 0
var _last_key: String = ""
var _previous_pause: bool = false
var _exit_reason: String = ""
var _exit_run: RunController
var _taking_over: bool = false
var _terminal_in_progress: bool = false
var _terminal_retry_run: RunController
var _history: CheckpointHistory = CheckpointHistory.new()
@onready var prompt: CheckpointPrompt = $CheckpointPrompt

func _ready() -> void:
	prompt.action_requested.connect(_on_prompt_action)

func _exit_tree() -> void:
	_epoch += 1
	if _job != null:
		_job.finish()
		_job = null

func configure(board: Board, requested: bool, directory: String) -> void:
	_board = board
	enabled = requested
	if not enabled: return
	if OS.has_feature("web"):
		var files: WEB_FILES = WEB_FILES.new(directory)
		var opened: Dictionary = await files.open()
		_store = CheckpointStore.new(directory, files)
		if not opened.ok: last_error = opened.reason
	else: _store = CheckpointStore.new(directory)
	_board.keep_checkpoint_history = true
	_board.checkpoint_reached.connect(_on_safe_point)
	_board.run_reset.connect(_on_run_reset)
	_refresh_metadata()
	var synced: Dictionary = await _store.sync()
	if not synced.ok: last_error = synced.reason

func is_busy() -> bool:
	return restoring or closing or _exit_saving or _transition or _terminal_in_progress or (_job != null and not _saving)

## Scene observers defer duplicate HUD refreshes only during the synchronous Board takeover.
func is_adopting() -> bool:
	return _taking_over

func arm_current() -> void:
	if not enabled: return
	_armed = true
	_on_safe_point(_board.run)

## Load exactly once in an isolated worker, then hand the validated candidate to Board once.
func continue_saved() -> bool:
	if not enabled: return false
	if is_busy(): return _reject_busy()
	restoring = true
	_previous_pause = get_tree().paused
	_board.can_selected = false
	_board.cancel_buffered_input("checkpoint_load")
	var epoch: int = _epoch
	prompt.open(&"checkpoint.loading")
	status_changed.emit(&"hud.status.checkpoint_loading")
	await _visible_frame()
	while _saving: await get_tree().process_frame
	if epoch != _epoch: return false
	var mode: GameModeDefinition = GameModes.find(saved_mode)
	if mode == null: return _load_failed("unsupported_mode")
	var policy_run: RunController = RunController.new(BoardRules.new(BoardState.new(_board.cols, _board.rows), MatchSystem.MIN_MATCH_COUNT), 0, mode.stage_config)
	var compatibility: Dictionary = RunCheckpointCodec.manifest(policy_run)
	_job = CheckpointJob.new()
	var resume_plan: Dictionary = resume_plan_provider.call() if resume_plan_provider.is_valid() else {}
	if _job.start_load(_store, compatibility, DESKTOP_BUDGET_USEC, resume_plan) != OK:
		_job = null
		return _load_failed("worker_unavailable")
	var result: Dictionary = await _join_job()
	if epoch != _epoch: return false
	if not result.ok: return _load_failed(result.reason)
	if result.run.initialization != "normal" or not result.run.prototype_profile.is_empty(): return _load_failed("unsupported_checkpoint_context")
	var adopting: int = Time.get_ticks_usec()
	before_restore.emit()
	_taking_over = true
	var adopted: bool = _board.adopt_checkpoint(result.run)
	_taking_over = false
	if not adopted: return _load_failed("takeover_rejected")
	_history = result.history
	_board.game_mode = GameModes.find(result.run.state.mode_id())
	_armed = true
	restoring = false
	last_error = ""
	get_tree().paused = false
	prompt.close()
	_last_key = ""
	last_resume_context = result.get("resume_context", {}).duplicate(true)
	restored.emit(result.run, result.fallback)
	last_job_metrics["resume_prepare_usec"] = result.get("resume_prepare_usec", 0)
	last_job_metrics["adoption_usec"] = Time.get_ticks_usec() - adopting
	print(("CHECKPOINT_WEB_RESTORE " if OS.has_feature("web") else "CHECKPOINT_DESKTOP_RESTORE ") + JSON.stringify(last_job_metrics))
	status_changed.emit(&"hud.status.checkpoint_fallback" if result.fallback else &"hud.status.checkpoint_restored")
	return true

## Prepared new-run rules must be constructed by the caller before invalidating the old identity.
func allow_new_run() -> bool:
	if not enabled: return true
	if is_busy(): return _reject_busy()
	_previous_pause = get_tree().paused
	_transition = true
	_queued.clear()
	var was_armed: bool = _armed
	_armed = false
	while _saving: await get_tree().process_frame
	var metadata: Dictionary = _store.inspect_latest()
	if metadata.ok or metadata.reason == "invalidation_pending" or was_armed:
		prompt.open(&"checkpoint.confirm_abandon", &"confirm")
		var answer: StringName = await prompt.action_requested
		if answer != &"confirm":
			_armed = was_armed
			_transition = false
			prompt.close()
			return false
	while metadata.ok or metadata.reason == "invalidation_pending":
		_last_key = ""
		var invalidated: Dictionary = await _invalidate_run(metadata.run_id, "restart")
		if invalidated.ok:
			metadata = invalidated
			break
		last_error = invalidated.reason
		prompt.open(&"checkpoint.reload_required" if _needs_reload() else &"checkpoint.invalidate_failed", &"blocked" if _needs_reload() else &"invalidate_failed")
		var answer: StringName = await prompt.action_requested
		if answer != &"retry":
			_transition = false
			_armed = was_armed
			prompt.close()
			return false
	if not metadata.ok and metadata.reason not in ["run_invalidated", "no_valid_checkpoint:missing"]:
		last_error = metadata.reason
		_transition = false
		_armed = was_armed
		prompt.open(&"checkpoint.load_failed", &"blocked")
		return false
	saved_available = false
	_transition = false
	prompt.close()
	return true

func request_exit(reason: String) -> void:
	if not enabled:
		exit_ready.emit(reason)
		return
	if is_busy(): return
	closing = true
	_previous_pause = get_tree().paused
	_exit_reason = reason
	_exit_run = _board.run
	_board.hold_at_checkpoint = true
	_board.can_selected = false
	_board.cancel_buffered_input("checkpoint_exit")
	_queued.clear()
	settling_exit.emit()
	get_tree().paused = false
	prompt.open(&"checkpoint.settling")
	_board.director.request_skip()
	if RunCheckpointCodec.safety_error(_exit_run).is_empty() or _exit_run.state.is_game_over or not _exit_run.state.rule_error.is_empty():
		_save_exit()
	else: _wait_for_exit_point()

func terminal(active: RunController, accepted_end: bool = false) -> void:
	if not enabled or active != _board.run: return
	if not active.state.is_game_over: return
	if active.can_continue_challenge() and not accepted_end: return
	if _terminal_in_progress: return
	_terminal_in_progress = true
	_queued.clear()
	_armed = false
	while _saving or _job != null: await get_tree().process_frame
	if active != _board.run:
		_terminal_in_progress = false
		return
	_last_key = ""
	var result: Dictionary = await _invalidate_run(active.state.run_id, "terminal")
	_terminal_in_progress = false
	saved_available = false
	if not result.ok:
		_terminal_retry_run = active
		last_error = result.reason
		prompt.open(&"checkpoint.reload_required" if _needs_reload() else &"checkpoint.terminal_failed", &"blocked" if _needs_reload() else &"terminal_failed")
		status_changed.emit(_failure_status())
	else:
		_terminal_retry_run = null
		last_error = ""
		prompt.close()
		status_changed.emit(&"hud.status.challenge_completed" if active.state.end_reason == &"challenge_completed" else &"hud.status.board_full")

func _on_safe_point(active: RunController) -> void:
	if not enabled or active != _board.run: return
	if closing:
		_save_exit()
		return
	if not _armed or restoring or _transition or active.initialization != "normal": return
	if _key(active) == _last_key: return
	_queued = _freeze(active)
	if not _queued.ok:
		last_error = _queued.reason
		_queued.clear()
		status_changed.emit(_failure_status())
		return
	if not _saving and _job == null: _drain_saves()

func _drain_saves() -> void:
	if _job != null or _saving: return
	_saving = true
	while not _queued.is_empty() and not restoring and not closing and not _transition:
		var encoded: Dictionary = _queued
		_queued = {}
		status_changed.emit(&"hud.status.checkpoint_saving")
		_job = CheckpointJob.new()
		if _job.start_save(_store, encoded, DESKTOP_BUDGET_USEC) != OK:
			_job = null
			last_error = "worker_unavailable"
			status_changed.emit(_failure_status())
			break
		var result: Dictionary = await _join_job()
		if result.ok:
			last_error = ""
			_last_key = String(encoded.payload.run_id) + ":" + String(encoded.payload.record_seq)
			saved_available = true
			saved_mode = StringName(encoded.manifest.mode_id)
			if not closing and not restoring and not _transition: status_changed.emit(&"hud.status.checkpoint_saved")
		else:
			last_error = result.reason
			status_changed.emit(_failure_status())
	_saving = false

func _save_exit() -> void:
	if _exit_saving or not closing: return
	_exit_saving = true
	await _visible_frame()
	while _saving: await get_tree().process_frame
	if not closing:
		_exit_saving = false
		return
	var result: Dictionary
	if _board.run != _exit_run: result = RunCheckpointCodec.failure("run_changed")
	elif _exit_run.can_continue_challenge(): result = RunCheckpointCodec.failure("challenge_decision_pending")
	elif _exit_run.state.is_game_over: result = await _invalidate_run(_exit_run.state.run_id, "terminal")
	elif _last_key == _key(_exit_run) and _exit_run.recorder != null and _exit_run.recorder.records.back().get("state") == RunSnapshot.capture(_exit_run):
		result = {"ok": true, "reason": "", "reused_validated_checkpoint": true}
	else:
		var encoded: Dictionary = _freeze(_exit_run)
		if not encoded.ok: result = encoded
		else:
			_job = CheckpointJob.new()
			if _job.start_save(_store, encoded, DESKTOP_BUDGET_USEC) != OK:
				_job = null
				result = RunCheckpointCodec.failure("worker_unavailable")
			else: result = await _join_job()
	_exit_saving = false
	if not closing: return
	if result.ok: exit_ready.emit(_exit_reason)
	else:
		last_error = result.reason
		prompt.open(&"checkpoint.reload_required" if _needs_reload() else (&"checkpoint.challenge_pending" if result.reason == "challenge_decision_pending" else &"checkpoint.exit_failed"), &"blocked" if _needs_reload() else &"save_failed")
		status_changed.emit(_failure_status())

func _invalidate_run(run_id: String, reason: String) -> Dictionary:
	var result: Dictionary = _store.invalidate(run_id, reason)
	var committed: Dictionary = await _store.sync()
	return result if committed.ok else RunCheckpointCodec.failure(committed.reason)

func _join_job() -> Dictionary:
	var current: CheckpointJob = _job
	var frames: int = 0
	var maximum_gap: int = 0
	var frame_started: int = Time.get_ticks_usec()
	var started: int = frame_started
	while not current.is_done():
		await get_tree().process_frame
		frames += 1
		maximum_gap = maxi(maximum_gap, Time.get_ticks_usec() - frame_started)
		frame_started = Time.get_ticks_usec()
	var result: Dictionary = current.finish()
	last_job_metrics = {"frames": frames, "maximum_gap_usec": maximum_gap, "elapsed_usec": Time.get_ticks_usec() - started, "freeze_usec": last_freeze_usec, "ok": result.ok}
	last_job_metrics["stages"] = {"decode": result.get("timing", {}), "package": result.get("package_timing", {}), "history_prime_usec": result.get("history_prime_usec", 0)}
	print(("CHECKPOINT_WEB_JOB " if OS.has_feature("web") else "CHECKPOINT_DESKTOP_JOB ") + JSON.stringify(last_job_metrics))
	if _job == current: _job = null
	if last_error == "worker_busy":
		last_error = ""
		status_changed.emit(&"hud.status.paused" if get_tree().paused else &"hud.status.ready")
	if not _queued.is_empty() and not _saving and not is_busy(): _drain_saves.call_deferred()
	return result

func _reject_busy() -> bool:
	last_error = "worker_busy"
	status_changed.emit(&"hud.status.checkpoint_waiting")
	return false

func _wait_for_exit_point() -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while closing and not _exit_saving:
		if Time.get_ticks_msec() > deadline or not _board.director.error.is_empty():
			last_error = "safe_point_unavailable"
			prompt.open(&"checkpoint.exit_failed", &"save_failed")
			return
		await get_tree().process_frame

func _visible_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _on_prompt_action(action: StringName) -> void:
	if _transition: return
	if action == &"retry" and _terminal_retry_run != null: terminal(_terminal_retry_run, true)
	elif action == &"leave_old" and _terminal_retry_run != null: exit_ready.emit("terminal_invalidation_unverified")
	elif action == &"retry" and closing: _save_exit()
	elif action == &"leave_old" and closing: exit_ready.emit(_exit_reason + ":old_checkpoint_retained")
	elif action == &"cancel":
		_terminal_retry_run = null
		_epoch += 1
		closing = false
		restoring = false
		_board.hold_at_checkpoint = false
		_board.can_selected = _board.run.state.phase == RunState.Phase.INPUT and not _board.run.state.is_game_over
		if _board.can_selected and _board.input_permission.is_valid(): _board.can_selected = bool(_board.input_permission.call(_board.run))
		get_tree().paused = _previous_pause
		prompt.close()
		operation_cancelled.emit()

func _load_failed(reason: String) -> bool:
	last_error = reason
	restoring = false
	get_tree().paused = _previous_pause
	prompt.open(&"checkpoint.reload_required" if _needs_reload() else &"checkpoint.load_failed", &"blocked")
	status_changed.emit(_failure_status())
	return false

func _needs_reload() -> bool:
	return last_error.ends_with("web_storage_conflict") or last_error.ends_with("web_storage_not_open")

func _failure_status() -> StringName:
	return &"hud.status.checkpoint_reload_required" if _needs_reload() else &"hud.status.checkpoint_failed"

func _refresh_metadata() -> void:
	var metadata: Dictionary = _store.inspect_latest()
	saved_available = metadata.ok
	if metadata.ok: saved_mode = StringName(metadata.manifest.get("mode_id", "stage_challenge"))
	elif metadata.reason not in ["no_valid_checkpoint:missing", "run_invalidated"]: last_error = metadata.reason

func _on_run_reset() -> void:
	if not _taking_over: _epoch += 1
	_armed = false
	_queued.clear()
	_last_key = ""
	_history = CheckpointHistory.new()
	_terminal_retry_run = null

func _key(active: RunController) -> String:
	return "" if active.recorder == null else active.state.run_id + ":" + str(active.recorder.records.size())

func _freeze(active: RunController) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var encoded: Dictionary = _history.freeze(active)
	if encoded.ok and trace_provider.is_valid(): encoded["telemetry"] = trace_provider.call(active).duplicate(true)
	last_freeze_usec = Time.get_ticks_usec() - started
	return encoded
