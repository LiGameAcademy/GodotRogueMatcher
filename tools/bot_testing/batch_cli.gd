extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "analyze":
		_analyze(args)
		return
	if args.size() > 0 and args[0] == "replay":
		if args.size() != 2:
			push_error("Usage: -- replay <JSONL path>")
			quit(2)
			return
		var replay: RuleReplay = RuleReplay.new()
		var success: bool = replay.replay_file(args[1])
		print(JSON.stringify({"success": success, "checked_records": replay.checked_records, "error": replay.error}))
		quit(0 if success else 1)
		return
	var count: int = 5
	var start_seed: int = 1
	var output: String = "user://bot_reports/latest"
	var move_limit: int = 300
	for arg: String in args:
		if arg.begins_with("--count="): count = arg.trim_prefix("--count=").to_int()
		elif arg.begins_with("--seed="): start_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--moves="): move_limit = arg.trim_prefix("--moves=").to_int()
	if count <= 0 or count > 1000 or move_limit <= 0:
		push_error("Invalid batch bounds")
		quit(2)
		return
	var analysis: RunAnalysis = RunAnalysis.new()
	var failures: int = 0
	for strategy_name: String in ["random", "greedy"]:
		for index: int in range(count):
			var strategy: RuleBot = RandomLegalBot.new(start_seed + index) if strategy_name == "random" else GreedyBot.new(start_seed + index)
			strategy.config = strategy.config.duplicate(true) as BotConfig
			strategy.config.move_limit = move_limit
			var runner: BotRunner = BotRunner.new()
			var recorder: RunRecorder = runner.play(start_seed + index, start_seed + index + 100000, strategy, true, false)
			# 实際落盘后再读回回放，而非只校验内存副本。
			var replay: RuleReplay = RuleReplay.new()
			if not replay.replay_file(recorder.path): runner.last_replay_error = replay.error
			if not runner.last_replay_error.is_empty(): failures += 1
			analysis.add(recorder.records, runner.last_replay_error)
			var footer: Dictionary = recorder.records.back()
			print("%s %d/%d seed=%d status=%s score=%s moves=%s replay=%s" % [strategy_name, index + 1, count, start_seed + index, footer.status, footer.score, footer.moves, runner.last_replay_error if not runner.last_replay_error.is_empty() else "OK"])
	if not analysis.write(output):
		push_error(analysis.error)
		quit(1)
		return
	print("REPORT=" + ProjectSettings.globalize_path(output))
	quit(0 if failures == 0 else 1)

## 按已生成的runs.csv选择局，重新读回验证和汇总，不重复代玩。
func _analyze(args: PackedStringArray) -> void:
	if args.size() != 3:
		push_error("Usage: -- analyze <runs.csv> <output directory>")
		quit(2)
		return
	var file: FileAccess = FileAccess.open(args[1], FileAccess.READ)
	if file == null:
		push_error("Cannot read runs.csv")
		quit(2)
		return
	var columns: PackedStringArray = file.get_csv_line()
	var id_column: int = columns.find("run_id")
	if id_column < 0:
		quit(2)
		return
	var analysis: RunAnalysis = RunAnalysis.new()
	var failures: int = 0
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() <= id_column or row[id_column].is_empty(): continue
		var id: String = row[id_column]
		if id.contains("/") or id.contains("\\") or id.contains(".."):
			failures += 1
			continue
		var replay: RuleReplay = RuleReplay.new()
		var records: Array[Dictionary] = replay.read_file("user://run_records/" + id + ".jsonl")
		var read_error: String = replay.error
		var valid: bool = replay.replay(records) if read_error.is_empty() else false
		var reason: String = read_error if not read_error.is_empty() else replay.error
		if not valid: failures += 1
		analysis.add(records, reason)
	if not analysis.write(args[2]):
		push_error(analysis.error)
		quit(1)
		return
	print("ANALYZED=%d REPLAY_FAILURES=%d REPORT=%s" % [analysis.runs.size(), failures, ProjectSettings.globalize_path(args[2])])
	quit(0 if failures == 0 else 1)
