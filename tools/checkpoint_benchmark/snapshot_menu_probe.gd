extends Node

## Agent-only real Game/menu/Board consumer test across page reloads on isolated origins.
## Uses the actual action/popup/queue/collection paths, accelerated presentation only.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const FILES: Script = preload("res://services/run_checkpoint/checkpoint_web_files.gd")
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const STATE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const SEGMENT: Script = preload("res://services/run_checkpoint/snapshot_segment.gd")
var _game: Node
var _board: Board
var _flow: GameCheckpointFlow
var _collection: RunCollection
var _finished: bool = false
var _details: Dictionary = {}
var _bot: GreedyBot = GreedyBot.new(18990)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(110.0).timeout.connect(func() -> void:
		if not _finished: _finish(false, "probe_watchdog_110s"))
	_run.call_deferred()

func _process(_delta: float) -> void:
	if _game != null and _game.is_inside_tree() and not _finished:
		if _board != null: _board.director.request_skip()
		(_game.get_node("UILayer/HUD") as Hud).finish_score_now()

func _run() -> void:
	var origin: String = str(JavaScriptBridge.eval("window.location.origin", true)) if OS.has_feature("web") else ""
	var mode: StringName = &"stage_challenge" if origin == "http://127.0.0.1:8991" else &"classic_endless"
	if origin not in ["http://127.0.0.1:8992", "http://127.0.0.1:8991"] or OS.get_cmdline_user_args() != PackedStringArray(["--snapshot-menu-probe"]):
		_finish(false, "probe_origin_or_args_rejected")
		return
	var files: FILES = FILES.new("user://snapshot-menu-probe")
	var opened: Dictionary = await files.open()
	if not opened.ok:
		_finish(false, opened.reason)
		return
	var store: CheckpointStore = CheckpointStore.new("user://snapshot-menu-probe", files)
	var metadata: Dictionary = store.inspect_latest()
	var reference: Dictionary = {}
	if metadata.ok:
		var policy: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 0, GameModes.find(mode).stage_config)
		reference = SNAPSHOT.load(store, SNAPSHOT.manifest(policy))
		if not reference.ok:
			_finish(false, reference.reason)
			return
	elif metadata.reason not in ["no_valid_checkpoint:missing", "run_invalidated"]:
		_finish(false, "probe_refuses_unknown_existing_slot:" + metadata.reason)
		return
	seed(899023)
	_game = GAME.instantiate()
	_game.set("persist_preferences", false)
	_game.set("record_runs", false)
	_game.set("collect_telemetry", true)
	_game.set("collection_context", "web_playtest")
	_game.set("show_start_menu", true)
	_game.set("enable_debug_fixtures", false)
	_game.set("enable_checkpoints", true)
	_game.set("use_snapshot_checkpoints", true)
	_game.set("checkpoint_directory", "user://snapshot-menu-probe")
	(_game.get_node("Board") as Board).game_mode = GameModes.find(mode)
	add_child(_game)
	_board = _game.get_node("Board") as Board
	_flow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	_collection = _game.get_node("RunCollection") as RunCollection
	var menu: ReleaseMenu = _game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	if not await _wait(func() -> bool: return menu.visible):
		_finish(false, "menu_not_ready")
		return
	_details = {"mode": String(mode), "candidate_flag": true, "default_flag_unchanged": true, "origin": origin, "menu_visible": true}
	if metadata.reason == "run_invalidated":
		_details["phase"] = "terminal_reopen_menu"
		_details["continue_unavailable"] = not _flow.saved_available
		_finish(not _flow.saved_available, "")
		return
	if metadata.ok:
		await _resume(reference, menu)
	else:
		menu.play_button.pressed.emit()
		if not await _wait(func() -> bool: return bool(_game.get("_has_played"))):
			_finish(false, "menu_play_not_started")
			return
		if not await _drive(true): return
		if not await _wait(_saved_idle):
			_finish(false, "snapshot_queue_not_confirmed")
			return
		var latest: Dictionary = SNAPSHOT.load(_flow.get("_store"), SNAPSHOT.manifest(_board.run))
		if not latest.ok:
			_finish(false, latest.reason)
			return
		_details.merge({"phase": "saved_frozen_reward", "run_id": _board.run.state.run_id, "seed": str(_board.run.state.random_streams.master_seed), "state_hash": RunSnapshot.digest(STATE.project(_board.run)), "snapshot_matches_live": STATE.project(latest.run) == STATE.project(_board.run), "trace_known": not latest.trace.is_empty(), "trace_parent_id": latest.trace.get("last_event_id", ""), "snapshot_schema": SNAPSHOT.SCHEMA, "job_metrics": _flow.last_job_metrics})
		_finish(_details.snapshot_matches_live and _details.trace_known, "")

func _resume(reference: Dictionary, menu: ReleaseMenu) -> void:
	var provisional: RunController = _board.run
	_details["provisional_recorders"] = 0 if provisional.recorder == null else 1
	_details["provisional_projectors"] = _collection.factory.projectors.size()
	menu.play_button.pressed.emit()
	if not await _wait(func() -> bool: return _board.run != provisional and not _flow.restoring and bool(_game.get("_has_played"))):
		_finish(false, "menu_resume_not_adopted:" + _flow.last_error)
		return
	if not await _wait(_choice_ready):
		_finish(false, "frozen_popup_not_ready")
		return
	var first: RunController = _board.run
	_details["endpoint_equal"] = STATE.project(first) == STATE.project(reference.run)
	_details["parent_known"] = _board.observation.telemetry.events[0].resume.lineage_known
	_details["resumed_header"] = first.recorder.records[0].kind
	var old_popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	var callbacks: Array[Dictionary] = []
	callbacks.assign(old_popup.skill_selected.get_connections())
	var old_offer: SkillOffer = first.state.rewards.active_offer
	var old_generation: int = _board.get("_generation")
	if not await _flow.continue_saved():
		_finish(false, "second_resume_failed:" + _flow.last_error)
		return
	if not await _wait(_choice_ready):
		_finish(false, "second_popup_not_ready")
		return
	var before: Dictionary = STATE.project(_board.run)
	for connection: Dictionary in callbacks:
		var callback: Callable = connection.callable
		if callback.is_valid(): callback.call(old_offer.offer_id, old_offer.choices[0].skill_id)
	_board.call("_commit_buffered_move", old_generation, 1, Vector2i.ZERO, 0, "old-probe-input")
	_details["old_callbacks_ignored"] = first.is_retired() and STATE.project(_board.run) == before
	var consumed: int = _board.run.state.rewards.consumed_count
	var current: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	var current_callbacks: Array[Dictionary] = []
	current_callbacks.assign(current.skill_selected.get_connections())
	var command: ChooseSkillCommand = _bot.choose(_board.run) as ChooseSkillCommand
	if command == null:
		_finish(false, "missing_choice_command")
		return
	_emit_choice(current, command)
	if not await _wait(func() -> bool: return _board.run.state.rewards.consumed_count == consumed + 1):
		_finish(false, "choice_not_consumed")
		return
	for connection: Dictionary in current_callbacks:
		var callback: Callable = connection.callable
		if callback.is_valid(): callback.call(command.offer_id, command.skill_id)
	_details["choice_consumed_once"] = _board.run.state.rewards.consumed_count == consumed + 1
	if not await _wait(func() -> bool: return _board.can_selected or _choice_ready() or _board.run.state.is_game_over):
		_finish(false, "post_choice_stuck")
		return
	if not await _verify_durable_segment(): return
	if not await _drive(false): return
	if _board.run.can_continue_challenge(): _flow.terminal(_board.run, true)
	if not await _wait(func() -> bool: return not _flow.is_busy() and not bool(_flow.get("_saving"))):
		_finish(false, "terminal_owner_pending")
		return
	var files: FILES = FILES.new("user://snapshot-menu-probe")
	var opened: Dictionary = await files.open()
	if not opened.ok:
		_finish(false, opened.reason)
		return
	var terminal: Dictionary = CheckpointStore.new("user://snapshot-menu-probe", files).inspect_latest()
	_details.merge({"phase": "resumed_then_terminal", "terminal_reason": String(_board.run.state.end_reason), "moves": _board.run.state.valid_moves, "terminal_durable": not terminal.ok and terminal.reason == "run_invalidated", "job_metrics": _flow.last_job_metrics})
	_finish(_details.endpoint_equal and _details.parent_known and _details.old_callbacks_ignored and _details.choice_consumed_once and _details.terminal_durable and _details.provisional_recorders == 0 and _details.provisional_projectors == 0, "")

func _drive(stop_at_reward: bool) -> bool:
	for index: int in range(900):
		if _board.run.state.is_game_over: return not stop_at_reward
		if not _board.run.state.rule_error.is_empty():
			_finish(false, _board.run.state.rule_error)
			return false
		if _board.run.state.rewards.active_offer != null:
			if not await _wait(_choice_ready):
				_finish(false, "drive_popup_not_ready")
				return false
			if stop_at_reward: return true
			var command: ChooseSkillCommand = _bot.choose(_board.run) as ChooseSkillCommand
			if command == null:
				_finish(false, "bot_choice_missing")
				return false
			_emit_choice(UIManager.current_popup as PopupSkillChoice, command)
		elif _board.can_selected:
			var command: RunCommand = _bot.choose(_board.run)
			if command == null or not await _board.call("_execute_action", command, 0.001):
				if _board.run.state.is_game_over: return not stop_at_reward
				if _board.run.state.phase != RunState.Phase.REWARDS:
					_finish(false, "board_action_rejected")
					return false
		await get_tree().process_frame
	_finish(false, "action_bound_reached")
	return false

func _emit_choice(popup: PopupSkillChoice, command: ChooseSkillCommand) -> void:
	if command.selected_color >= 0: popup.color_skill_selected.emit(command.offer_id, command.skill_id, command.selected_color)
	else: popup.skill_selected.emit(command.offer_id, command.skill_id)

func _verify_durable_segment() -> bool:
	_collection.flush()
	var support: RefCounted = _collection.get("_web")
	if not await _wait(func() -> bool: return not bool(support.call("pending"))):
		_finish(false, "new_segment_not_acknowledged")
		return false
	var snapshot: Dictionary = await support.get("backend").snapshot()
	if not snapshot.ok:
		_finish(false, snapshot.reason)
		return false
	var id: String = _collection.factory.session_id
	var name: String = "run_records/" + _board.run.state.run_id + "--" + id + ".jsonl"
	if not snapshot.files.has(name):
		_finish(false, "new_command_segment_missing")
		return false
	var rows: Array[Dictionary] = []
	for line: String in String(snapshot.files[name]).strip_edges().split("\n"):
		var value: Variant = JSON.parse_string(line)
		if not value is Dictionary:
			_finish(false, "new_command_segment_bad_json")
			return false
		rows.append(value)
	var verified: Dictionary = SEGMENT.replay(rows, SNAPSHOT.manifest(_board.run))
	_details["durable_new_segment_replay"] = verified.ok
	_details["durable_new_segment_rows"] = rows.size()
	_details["durable_new_segment_sha256"] = String(snapshot.files[name]).sha256_text()
	if not verified.ok: _finish(false, "new_segment_replay:" + verified.reason)
	return verified.ok

func _choice_ready() -> bool:
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	return is_instance_valid(popup) and popup.offer != null and not popup.skill_selected.get_connections().is_empty()

func _saved_idle() -> bool:
	return _flow.saved_available and not bool(_flow.get("_saving")) and _flow.get("_job") == null and (_flow.get("_queued") as Dictionary).is_empty()

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())

func _finish(ok: bool, reason: String) -> void:
	if _finished: return
	_finished = true
	print("SNAPSHOT_MENU_REPORT " + JSON.stringify({"ok": ok, "reason": reason, "details": _details, "scope": "bounded agent-driven actual Game/menu/Board candidate, accelerated presentation; not default rollout or human acceptance"}))