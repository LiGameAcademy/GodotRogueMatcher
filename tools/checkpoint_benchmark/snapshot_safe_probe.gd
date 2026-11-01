extends Node

## Bounded, agent-only snapshot kernel probe. Never opens an author/product origin.
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const RESTORE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const WEB_FILES: Script = preload("res://services/run_checkpoint/checkpoint_web_files.gd")
const SEGMENT: Script = preload("res://services/run_checkpoint/snapshot_segment.gd")
var _finished: bool = false
var _directory: String = "user://snapshot-safe-probe-classic"
var _samples: Array[Dictionary] = []

func _ready() -> void:
	print("SNAPSHOT_SAFE_PROGRESS ready")
	get_tree().create_timer(60.0).timeout.connect(_timeout)
	_run.call_deferred()

func _run() -> void:
	var origin: String = str(JavaScriptBridge.eval("window.location.origin", true)) if OS.has_feature("web") else ""
	var stage_mode: bool = origin == "http://127.0.0.1:8983"
	var arguments: PackedStringArray = PackedStringArray(["--snapshot-safe-probe", "--stage" if stage_mode else "--classic"])
	if origin not in ["http://127.0.0.1:8982", "http://127.0.0.1:8983"] or OS.get_cmdline_user_args() != arguments:
		_finish(false, "probe_origin_or_arguments_rejected")
		return
	print("SNAPSHOT_SAFE_PROGRESS open")
	var files: WEB_FILES = WEB_FILES.new(_directory)
	var opened: Dictionary = await files.open()
	print("SNAPSHOT_SAFE_PROGRESS opened " + str(opened.ok))
	if not opened.ok:
		_finish(false, opened.reason)
		return
	var store: CheckpointStore = CheckpointStore.new(_directory, files)
	var found: Dictionary = store.inspect_latest()
	if found.ok or found.reason != "no_valid_checkpoint:missing":
		_finish(false, "probe_requires_empty_slot_no_overwrite")
		return
	var config: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres") if stage_mode else null
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, config)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "snapshot_probe", false, Engine.get_version_info().hash)
	var bot: GreedyBot = GreedyBot.new(100023)
	var targets: Array[int] = [0]
	if not stage_mode: targets.append(45)
	for target: int in targets:
		for index: int in range(400):
			if not _reach_input(run, bot):
				_finish(false, "probe_did_not_reach_input")
				return
			if run.state.valid_moves >= target: break
			var command: RunCommand = bot.choose(run)
			if command == null or not run.execute_command(command).accepted:
				_finish(false, "probe_command_rejected")
				return
			await get_tree().process_frame
		if run.state.valid_moves != target:
			_finish(false, "probe_action_bound")
			return
		var result: Dictionary = await _measure(store, run, bot)
		_samples.append(result)
		if not result.ok:
			_finish(false, result.reason)
			return
	if not await _seek_reward(run, bot):
		_finish(false, "frozen_reward_not_reached")
		return
	var frozen_result: Dictionary = await _measure(store, run, bot)
	_samples.append(frozen_result)
	_finish(frozen_result.ok, frozen_result.reason)

func _measure(store: CheckpointStore, run: RunController, bot: GreedyBot) -> Dictionary:
	print("SNAPSHOT_SAFE_PROGRESS measure " + str(run.state.phase) + " moves=" + str(run.state.valid_moves))
	var before: Dictionary = RESTORE.project(run)
	var source_records: int = run.recorder.records.size()
	var box: Array[Dictionary] = [{}]
	var started: int = Time.get_ticks_usec()
	var frame: int = started
	var maximum: int = 0
	_save.call_deferred(store, run, box)
	while box[0].is_empty():
		await get_tree().process_frame
		maximum = maxi(maximum, Time.get_ticks_usec() - frame)
		frame = Time.get_ticks_usec()
	var saved: Dictionary = box[0]
	print("SNAPSHOT_SAFE_PROGRESS saved " + str(saved.ok))
	var elapsed: int = Time.get_ticks_usec() - started
	if not saved.ok: return saved
	var result: Dictionary = {"ok": true, "reason": "", "mode": String(run.state.mode_id()), "phase": str(run.state.phase), "continuation": String(run.continuation), "reward_id": "0" if run.state.rewards.active_offer == null else str(run.state.rewards.active_offer.reward_id), "moves": run.state.valid_moves, "source_records_not_saved": source_records, "snapshot_bytes": saved.snapshot_bytes, "save_usec": elapsed, "save_maximum_gap_usec": maximum, "source_unchanged": RESTORE.project(run) == before, "state_hash": RunSnapshot.digest(before)}
	box = [{}]
	started = Time.get_ticks_usec()
	frame = started
	maximum = 0
	_load.call_deferred(SNAPSHOT.manifest(run), box)
	while box[0].is_empty():
		await get_tree().process_frame
		maximum = maxi(maximum, Time.get_ticks_usec() - frame)
		frame = Time.get_ticks_usec()
	result["load_with_fresh_open_usec"] = Time.get_ticks_usec() - started
	result["load_maximum_gap_usec"] = maximum
	var loaded: Dictionary = box[0]
	print("SNAPSHOT_SAFE_PROGRESS loaded " + str(loaded.ok))
	if not loaded.ok: return loaded
	result["endpoint_equal"] = RESTORE.project(loaded.run) == before
	var segment: Dictionary = SEGMENT.begin(loaded.run, "probe-segment-" + str(_samples.size()))
	if not segment.ok: return segment
	var next_commands: int = 0
	for index: int in range(3):
		if not _same_input(run, loaded.run, bot): return {"ok": false, "reason": "next_input_mismatch"}
		var command: RunCommand = bot.choose(run)
		if command == null: return {"ok": false, "reason": "missing_next_command"}
		var copied: RunCommand = CommandCodec.decode(CommandCodec.encode(command))
		if run.execute_command(command).accepted != loaded.run.execute_command(copied).accepted: return {"ok": false, "reason": "next_command_mismatch"}
		if RESTORE.project(run) != RESTORE.project(loaded.run): return {"ok": false, "reason": "next_state_mismatch"}
		next_commands += 1
	result["identical_next_commands"] = next_commands
	var replayed: Dictionary = SEGMENT.replay(loaded.run.recorder.records, SNAPSHOT.manifest(run))
	result["segment_replay_ok"] = replayed.ok
	if not replayed.ok: return replayed
	result.ok = result.source_unchanged and result.endpoint_equal
	return result

func _save(store: CheckpointStore, run: RunController, box: Array[Dictionary]) -> void:
	box[0] = await SNAPSHOT.save(store, run)

func _load(compatibility: Dictionary, box: Array[Dictionary]) -> void:
	print("SNAPSHOT_SAFE_PROGRESS open")
	var files: WEB_FILES = WEB_FILES.new(_directory)
	var opened: Dictionary = await files.open()
	print("SNAPSHOT_SAFE_PROGRESS opened " + str(opened.ok))
	box[0] = SNAPSHOT.load(CheckpointStore.new(_directory, files), compatibility) if opened.ok else opened

func _reach_input(run: RunController, bot: GreedyBot) -> bool:
	for index: int in range(100):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): return false
		if run.state.phase == RunState.Phase.INPUT: return true
		if run.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(run)
			if command == null or not run.execute_command(command).accepted: return false
		else: run.advance()
	return false

func _same_input(a: RunController, b: RunController, bot: GreedyBot) -> bool:
	for index: int in range(100):
		if a.state.is_game_over or b.state.is_game_over or RESTORE.project(a) != RESTORE.project(b): return false
		if a.state.phase == RunState.Phase.INPUT: return b.state.phase == RunState.Phase.INPUT
		if a.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(a)
			if command == null or a.execute_command(command).accepted != b.execute_command(CommandCodec.decode(CommandCodec.encode(command))).accepted: return false
		else:
			a.advance()
			b.advance()
	return false

func _seek_reward(run: RunController, bot: GreedyBot) -> bool:
	for index: int in range(400):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): return false
		if run.state.rewards.active_offer != null: return true
		if run.state.phase == RunState.Phase.INPUT:
			var command: RunCommand = bot.choose(run)
			if command == null or not run.execute_command(command).accepted: return false
		else: run.advance()
		await get_tree().process_frame
	return false
func _timeout() -> void:
	if not _finished: _finish(false, "probe_watchdog_60_seconds")

func _finish(ok: bool, reason: String) -> void:
	_finished = true
	print("SNAPSHOT_SAFE_WEB_REPORT " + JSON.stringify({"ok": ok, "reason": reason, "samples": _samples, "scope": "bounded agent-only snapshot safe-points/segment/IndexedDB probe; not live menu or whole O5 acceptance"}))
	get_tree().quit(0 if ok else 2)
