extends RefCounted

## Generates fresh synthetic records through current commands, never rewrites historical evidence.
## UI-like sources exercise parsing only; every generated header explicitly marks synthetic data.
const FIXTURE: Script = preload("res://tests/support/screening_fixture.gd")

static func write(directory: String, name: String) -> String:
	var key: String = "t"
	var task: String = "overlap"
	var actions: int = 1
	var reason: String = "fixed_complete"
	var ui: bool = name.begins_with("ui-")
	if name.begins_with("free-"):
		key = name.trim_prefix("free-")
		task = "free"
		actions = 15
		reason = "action_limit"
	elif name == "ui-action-limit":
		key = "l"
		task = "free"
		reason = "action_limit"
	elif name == "ui-time-paused":
		key = "baseline"
		task = "free"
		actions = 0
		reason = "time_limit"
	elif not ui:
		task = name.trim_prefix("t-")
	var run: RunController = ScreeningDeck.new_run(key, task)
	run.recorder = RunRecorder.new()
	run.recorder.metadata = {"synthetic": true, "purpose": "current protocol parser regression; no participant observation"}
	run.recorder.begin(run, "screening_playground" if ui else "screening_automated_fixture", false, "synthetic-test")
	var bot: RandomLegalBot = RandomLegalBot.new(119)
	for index: int in range(actions):
		if task == "free":
			if not run.execute_command(bot.choose(run)).accepted: return ""
		else:
			if not FIXTURE.move(run).accepted: return ""
		for step: int in range(30):
			if run.state.phase == RunState.Phase.INPUT: break
			if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer != null:
				if not run.execute_command(bot.choose(run)).accepted: return ""
			run.advance()
	run.recorder.finish(run, "censored", "screening_" + reason)
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return ""
	var path: String = directory.path_join(name + ".jsonl")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	for record: Dictionary in run.recorder.records: file.store_line(JSON.stringify(record))
	file.close()
	if ui:
		var side: Dictionary = {"run_id": run.state.run_id, "config_id": "screening-%s-v1" % key,
			"task": task, "actions": actions, "elapsed_ms": 4 if actions == 0 else 88,
			"reason": reason, "record_error": "", "synthetic": true}
		file = FileAccess.open(path.get_basename() + "-screening.json", FileAccess.WRITE)
		if file == null: return ""
		file.store_string(JSON.stringify(side))
		file.close()
	return path
