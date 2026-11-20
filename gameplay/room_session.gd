extends "res://gameplay/game.gd"

## Playable session entered from the preparation room. The CoreSystem handoff
## arrives before tree entry, so it must only store data and startup options.
const PREPARATION_ROOM: String = "res://ui/preparation_room/preparation_room.tscn"
var _request: Dictionary
var _returning: bool = false
var _select_on_return: bool = false
var _confirming_result: bool = false

func _ready() -> void:
	_checkpoint.track_visits = true
	_hud.hide()
	if not _request.is_empty():
		await CoreSystem.scene_manager.scene_loading_finished
	await super._ready()

func init_state(data: Dictionary) -> void:
	_request = data.duplicate(true)
	checkpoint_directory = data.get("directory", "user://run_checkpoint")
	enable_checkpoints = true
	use_snapshot_checkpoints = true
	show_start_menu = false
	intercept_window_close = true
	record_runs = not OS.has_feature("web")
	collection_context = "web_playtest" if OS.has_feature("web") else ("desktop_playtest" if OS.has_feature("template") else "editor_playtest")

func _start_session() -> void:
	CoreSystem.scene_manager.scene_loading_failed.connect(_on_scene_load_failed)
	_hud.hide()
	if _request.get("action") == "continue":
		if await _checkpoint.continue_saved():
			_has_played = true
			_hud.show()
		else:
			await _checkpoint.prompt.action_requested
			_return_to_room()
		return
	var mode: GameModeDefinition = GameModes.find(StringName(_request.get("mode", "")))
	var opening: StringName = StringName(_request.get("opening", ""))
	if _request.get("action") != "new" or mode == null or not _checkpoint.opening_progress.available(opening) or (opening != &"standard" and mode.mode_id != &"stage_challenge"):
		await _opening_failed()
		return
	_board.game_mode = mode
	board_rules = BoardRules.new(BoardState.new(_board.cols, _board.rows), MatchSystem.MIN_MATCH_COUNT)
	var prepared: Dictionary = NewRunFactory.prepare(board_rules, mode.stage_config, _board.new_run_seeds, null, null, _checkpoint.previous_master_seed(), opening)
	if not prepared.ok:
		await _opening_failed()
		return
	var active: RunController = prepared.run
	# Freeze the first offer on an independent copy so a live replay still
	# records its generation at the player's normal first reward action.
	var snapshot_run: RunController = active
	if active.state.pending_rewards > 0:
		var rules_copy: BoardRules = BoardRules.new(BoardState.new(_board.cols, _board.rows), MatchSystem.MIN_MATCH_COUNT)
		snapshot_run = RunController.new(rules_copy, active.state.random_streams.master_seed, mode.stage_config)
		snapshot_run.initialize("normal", opening)
		snapshot_run.state.run_id = active.state.run_id
		snapshot_run.prepare_offer(false)
	var committed: Dictionary = await _checkpoint.commit_opening(snapshot_run, _request.get("replace", ""))
	if not committed.ok:
		push_warning("Preparation room checkpoint: " + String(committed.reason))
		await _opening_failed()
		return
	_board.telemetry_factory = _collection.factory if collect_telemetry else null
	_hud.show()
	await _board.start_game(board_rules, record_runs, active, prepared.initial)
	_has_played = true
	_checkpoint.arm_current()
	if _board.observation.telemetry != null: _board.observation.telemetry.play_started()

func _opening_failed() -> void:
	_select_on_return = true
	_checkpoint.prompt.open(&"room.start_failed", &"blocked")
	await _checkpoint.prompt.action_requested
	_return_to_room()

func _on_game_over() -> void:
	if not GameFlow.show_result(): return
	await super._on_game_over()

func _continue_challenge() -> void:
	if not _board.run.can_continue_challenge(): return
	GameFlow.continue_challenge()
	await super._continue_challenge()

func _end_to_menu() -> void:
	if _confirming_result or _returning or GameFlow.machine.current != GameFlow.Page.RESULT: return
	_confirming_result = true
	var seen: bool = _checkpoint.opening_unlocked_run == _board.run.state.run_id
	await _checkpoint.terminal(_board.run, true)
	_confirming_result = false
	if not GameNewRunFlow.result_can_close(_checkpoint, _board.run, seen, UIManager.current_popup): return
	_return_to_room()

func _on_retry_requested() -> bool:
	_select_on_return = true
	if _board.run.state.is_game_over:
		await _end_to_menu()
	else:
		_checkpoint.request_exit("prepare_new")
	return true

func _play_from_menu(new_run: bool) -> void:
	if new_run:
		_select_on_return = true
		_checkpoint.request_exit("prepare_new")
	else: await super._play_from_menu(false)

func _finish_quit(reason: String) -> void:
	if reason.begins_with("prepare_new"):
		_suspend_collection()
		_return_to_room()
	else: super._finish_quit(reason)

func _quit(reason: String) -> void:
	if _board.run == null: return
	super._quit(reason)

func _return_to_room() -> void:
	if _returning: return
	_returning = true
	var mode_id: StringName = _board.game_mode.mode_id if _board.run != null else StringName(_request.get("mode", "stage_challenge"))
	if not GameFlow.travel(GameFlow.Page.ROOM, {"select": _select_on_return, "mode": mode_id, "opening": _request.get("opening", "standard"), "directory": checkpoint_directory}):
		_returning = false
		return
	if _returning:
		UIManager.close_popup()
		get_tree().paused = false
		_menu_owns_pause = false

func _on_scene_load_failed(path: String, _reason: String) -> void:
	if not _returning or path != PREPARATION_ROOM: return
	_returning = false
	_checkpoint.prompt.open(&"room.return_failed", &"blocked")
	await _checkpoint.prompt.action_requested
	_return_to_room()
