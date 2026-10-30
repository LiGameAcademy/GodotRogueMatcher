extends SceneTree

## Measures real normal-initialized rules, not fixture availability or human play duration.
## Runs only in an explicitly isolated APPDATA; leaves ordinary player slots untouched.
const MAX_ACTIONS: int = 200
const MAX_COMMANDS: int = 800
const MAX_SAMPLE_USEC: int = 90000000
const SAVE_ACTIONS: Array[int] = [0, 25, 50, 75, 90, 95, 100, 150, 200]
var _results: Array[Dictionary] = []
var _desktop: bool = false
var _budget_usec: int = RunCheckpointCodec.REBUILD_BUDGET_USEC
var _long_only: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_desktop = OS.get_cmdline_user_args().has("--desktop")
	_long_only = OS.get_cmdline_user_args().has("--long-only")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--budget-us="):
			var value: String = arg.trim_prefix("--budget-us=")
			if not CommandCodec.valid_integer(value) or value.to_int() <= 0:
				quit(2)
				return
			_budget_usec = value.to_int()
	for stage: bool in [false, true]:
		for seed_value: int in [7, 23]:
			if _long_only and (stage or seed_value != 23): continue
			var sample: Dictionary = await _sample(seed_value, stage)
			_results.append(sample)
			_write()
			print("CHECKPOINT_SAMPLE " + JSON.stringify(sample))
	quit()

func _sample(seed_value: int, stage: bool) -> Dictionary:
	var config: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres") if stage else null
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, config)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_benchmark", false)
	var bot: GreedyBot = GreedyBot.new(seed_value + 100000)
	var directory: String = "user://checkpoint-benchmark/%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), seed_value]
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), RunCheckpointCodec.manifest(run))
	if _desktop: session.rebuild_budget_usec = _budget_usec
	var measurements: Array[Dictionary] = []
	var history: CheckpointHistory = CheckpointHistory.new()
	var maximum_freeze_usec: int = 0
	var measured: Dictionary[int, bool] = {}
	var started: int = Time.get_ticks_usec()
	var commands: int = 0
	var last_progress: int = -1
	var stop: String = "action_limit"
	while run.state.valid_moves + run.state.activations <= MAX_ACTIONS and commands < MAX_COMMANDS:
		if Time.get_ticks_usec() - started > MAX_SAMPLE_USEC:
			stop = "benchmark_time_limit"
			break
		if not run.state.rule_error.is_empty():
			stop = "rule_error"
			break
		if run.state.is_game_over:
			stop = String(run.state.end_reason)
			break
		var action: int = run.state.valid_moves + run.state.activations
		if action / 25 != last_progress:
			last_progress = action / 25
			print("CHECKPOINT_PROGRESS %s seed=%d actions=%d records=%d" % [run.state.mode_id(), seed_value, action, run.recorder.records.size()])
		if RunCheckpointCodec.safety_error(run).is_empty():
			if _desktop:
				var freeze_started: int = Time.get_ticks_usec()
				history.freeze(run)
				maximum_freeze_usec = maxi(maximum_freeze_usec, Time.get_ticks_usec() - freeze_started)
			if (action in SAVE_ACTIONS and not measured.has(action)) or run.recorder.records.size() > RunCheckpointCodec.MAX_RECORDS:
				var measurement: Dictionary = await _measure(run, session, directory, history)
				measurements.append(measurement)
				measured[action] = true
				if not measurement.ok:
					stop = "checkpoint_limit_or_failure"
					break
			if action >= MAX_ACTIONS: break
		if run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS] and (run.state.phase != RunState.Phase.REWARDS or run.state.rewards.active_offer != null):
			var command: RunCommand = bot.choose(run)
			if command == null:
				stop = "no_legal_bot_command"
				break
			var result: CommandResult = run.execute_command(command)
			commands += 1
			if not result.accepted:
				stop = "bot_command_rejected:" + result.reason
				break
		else:
			run.advance()
	return {
		"mode": String(run.state.mode_id()), "seed": str(seed_value), "source": "normal_rules_greedy_bot",
		"budget_usec": _budget_usec if _desktop else RunCheckpointCodec.REBUILD_BUDGET_USEC,
		"rules": RunSnapshot.RULES_VERSION, "rng": RunRandomStreams.SCHEME_VERSION,
		"config_hash": RunCheckpointCodec.manifest(run).config_hash,
		"actions": run.state.valid_moves + run.state.activations, "commands": commands,
		"records": run.recorder.records.size(), "score": str(run.state.ledger.total),
		"stop": stop, "game_over": run.state.is_game_over, "rule_error": run.state.rule_error,
		"elapsed_usec": Time.get_ticks_usec() - started, "measurements": measurements,
		"maximum_scene_freeze_usec": maximum_freeze_usec, "freeze_mode": "incremental_readonly_history" if _desktop else "full_value_copy",
	}

func _measure(run: RunController, session: RunCheckpointSession, directory: String, history: CheckpointHistory) -> Dictionary:
	var primary: String = directory.path_join("primary.json")
	var previous: String = directory.path_join("previous.json")
	var old_pair: Array[String] = [FileAccess.get_sha256(primary) if FileAccess.file_exists(primary) else "", FileAccess.get_sha256(previous) if FileAccess.file_exists(previous) else ""]
	var before: Dictionary = RunSnapshot.capture(run)
	var started: int = Time.get_ticks_usec()
	var saved: Dictionary
	var freeze_usec: int = 0
	var save_frames: int = 0
	var save_max_gap_usec: int = 0
	if _desktop:
		var encoded: Dictionary = history.freeze(run)
		freeze_usec = Time.get_ticks_usec() - started
		if encoded.ok:
			var worker: CheckpointJob = CheckpointJob.new()
			worker.start_save(session._store, encoded, session.rebuild_budget_usec)
			var frame_started: int = Time.get_ticks_usec()
			while not worker.is_done():
				await process_frame
				save_frames += 1
				save_max_gap_usec = maxi(save_max_gap_usec, Time.get_ticks_usec() - frame_started)
				frame_started = Time.get_ticks_usec()
			saved = worker.finish()
		else: saved = encoded
	else: saved = session.save(run)
	var elapsed: int = Time.get_ticks_usec() - started
	var result: Dictionary = {
		"actions": run.state.valid_moves + run.state.activations, "records": run.recorder.records.size(),
		"point": "input" if run.state.phase == RunState.Phase.INPUT else "frozen_reward",
		"ok": saved.ok, "reason": saved.reason, "save_usec": elapsed,
		"rebuild_usec": saved.get("rebuild_usec"), "source_unchanged": before == RunSnapshot.capture(run),
		"desktop_worker": _desktop, "main_freeze_usec": freeze_usec,
		"save_progress_frames": save_frames, "save_max_frame_gap_usec": save_max_gap_usec,
	}
	if saved.ok:
		var file: FileAccess = FileAccess.open(primary, FileAccess.READ)
		result["file_bytes"] = file.get_length()
		file.close()
		var restored: Dictionary
		if _desktop:
			var worker: CheckpointJob = CheckpointJob.new()
			worker.start_load(session._store, session._manifest, session.rebuild_budget_usec)
			var frames: int = 0
			var gap_usec: int = 0
			var frame_started: int = Time.get_ticks_usec()
			while not worker.is_done():
				await process_frame
				frames += 1
				gap_usec = maxi(gap_usec, Time.get_ticks_usec() - frame_started)
				frame_started = Time.get_ticks_usec()
			restored = worker.finish()
			result["load_progress_frames"] = frames
			result["load_max_frame_gap_usec"] = gap_usec
		else: restored = session.load_candidate()
		result["load_ok"] = restored.ok
		result["load_reason"] = restored.reason
		result["load_rebuild_usec"] = restored.get("rebuild_usec")
		result["endpoint_equal"] = restored.ok and before == RunSnapshot.capture(restored.run)
		result["ok"] = restored.ok
		if not restored.ok: result["reason"] = "load:" + restored.reason
	else:
		var current_pair: Array[String] = [FileAccess.get_sha256(primary) if FileAccess.file_exists(primary) else "", FileAccess.get_sha256(previous) if FileAccess.file_exists(previous) else ""]
		result["old_pair_preserved"] = old_pair == current_pair
		var restored: Dictionary = session.load_candidate()
		result["old_checkpoint_load_ok"] = restored.ok
	return result

func _write() -> void:
	var output: String = "res://.godot/checkpoint-benchmark-desktop-long.json" if _long_only else ("res://.godot/checkpoint-benchmark-desktop.json" if _desktop else "res://.godot/checkpoint-benchmark.json")
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "samples": _results}, "\t", true, true))
	file.close()
