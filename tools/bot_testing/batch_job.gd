extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "analyze":
		_analyze(args)
		return
	if args.size() > 0 and args[0] == "replay":
		if args.size() != 2:
			push_error("Usage: -- replay <JSONL path>")
			get_tree().quit(2)
			return
		var replay: RuleReplay = RuleReplay.new()
		var success: bool = replay.replay_file(args[1])
		print(JSON.stringify({"success": success, "checked_records": replay.checked_records, "error": replay.error}))
		get_tree().quit(0 if success else 1)
		return
	var count: int = 5
	var start_seed: int = 1
	var output: String = "user://bot_reports/latest"
	var move_limit: int = 300
	var telemetry_output: String = TelemetryFactory.CONFIG.local_directory
	var record_output: String = "user://run_records"
	var selected_strategy: String = "both"
	var commit_id: String = "unknown"
	for arg: String in args:
		if arg.begins_with("--count=") or arg.begins_with("--seed=") or arg.begins_with("--moves="):
			if not CommandCodec.valid_integer(arg.get_slice("=", 1)):
				push_error("Invalid decimal integer: " + arg)
				get_tree().quit(2)
				return
		if arg.begins_with("--count="): count = arg.trim_prefix("--count=").to_int()
		elif arg.begins_with("--seed="): start_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--moves="): move_limit = arg.trim_prefix("--moves=").to_int()
		elif arg.begins_with("--telemetry-output="): telemetry_output = arg.trim_prefix("--telemetry-output=")
		elif arg.begins_with("--record-output="): record_output = arg.trim_prefix("--record-output=")
		elif arg.begins_with("--strategy="): selected_strategy = arg.trim_prefix("--strategy=")
		elif arg.begins_with("--commit="): commit_id = arg.trim_prefix("--commit=")
	if count <= 0 or count > 1000 or move_limit <= 0 or selected_strategy not in ["both", "random", "greedy"]:
		push_error("Invalid batch bounds")
		get_tree().quit(2)
		return
	var analysis: RunAnalysis = RunAnalysis.new()
	var pressure_report: PressureBatchReport = PressureBatchReport.new()
	var failures: int = 0
	var telemetry_factory: TelemetryFactory = TelemetryFactory.new()
	telemetry_factory.directory = telemetry_output
	telemetry_factory.record_directory = record_output
	telemetry_factory.commit_id = commit_id
	for strategy_name: String in ["random", "greedy"]:
		if selected_strategy != "both" and selected_strategy != strategy_name: continue
		for index: int in range(count):
			var strategy: RuleBot = RandomLegalBot.new(start_seed + index) if strategy_name == "random" else GreedyBot.new(start_seed + index)
			strategy.config = strategy.config.duplicate(true) as BotConfig
			strategy.config.move_limit = move_limit
			var runner: BotRunner = BotRunner.new()
			runner.stage_config = null if args.has("--legacy") else preload("res://gameplay/progression/stages/stage_config.tres")
			runner.telemetry_factory = telemetry_factory
			var recorder: RunRecorder = runner.play(start_seed + index, start_seed + index + 100000, strategy, true, false)
			# 实際落盘后再读回回放，而非只校验内存副本。
			var replay: RuleReplay = RuleReplay.new()
			if not replay.replay_file(recorder.path): runner.last_replay_error = replay.error
			if not runner.last_replay_error.is_empty() or not recorder.error.is_empty() or not runner.last_telemetry.error.is_empty() or recorder.records.back().status == "rule_error": failures += 1
			analysis.add(recorder.records, runner.last_replay_error)
			pressure_report.add(recorder, runner.last_telemetry, runner.last_replay_error)
			var footer: Dictionary = recorder.records.back()
			print("%s %d/%d seed=%d status=%s score=%s moves=%s replay=%s" % [strategy_name, index + 1, count, start_seed + index, footer.status, footer.score, footer.moves, runner.last_replay_error if not runner.last_replay_error.is_empty() else "OK"])
	if not analysis.write(output) or not pressure_report.write(output):
		push_error(analysis.error)
		get_tree().quit(1)
		return
	print("REPORT=" + ProjectSettings.globalize_path(output))
	get_tree().quit(0 if failures == 0 else 1)

## 按已生成的runs.csv选择局，重新读回验证和汇总，不重复代玩。
func _analyze(args: PackedStringArray) -> void:
	if args.size() not in [3, 4]:
		push_error("Usage: -- analyze <runs.csv> <output directory> [record directory]")
		get_tree().quit(2)
		return
	var file: FileAccess = FileAccess.open(args[1], FileAccess.READ)
	if file == null:
		push_error("Cannot read runs.csv")
		get_tree().quit(2)
		return
	var columns: PackedStringArray = file.get_csv_line()
	var id_column: int = columns.find("run_id")
	if id_column < 0:
		get_tree().quit(2)
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
		var directory: String = args[3] if args.size() == 4 else "user://run_records"
		var records: Array[Dictionary] = replay.read_file(directory.path_join(id + ".jsonl"))
		var read_error: String = replay.error
		var valid: bool = replay.replay(records) if read_error.is_empty() else false
		var reason: String = read_error if not read_error.is_empty() else replay.error
		if not valid: failures += 1
		analysis.add(records, reason)
	if not analysis.write(args[2]):
		push_error(analysis.error)
		get_tree().quit(1)
		return
	print("ANALYZED=%d REPLAY_FAILURES=%d REPORT=%s" % [analysis.runs.size(), failures, ProjectSettings.globalize_path(args[2])])
	get_tree().quit(0 if failures == 0 else 1)
