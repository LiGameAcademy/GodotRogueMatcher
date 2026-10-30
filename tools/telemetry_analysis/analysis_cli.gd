extends SceneTree

const BOUNDED: Script = preload("res://tools/telemetry_analysis/bounded_analysis.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0] == "--bounded":
		_bounded(args)
		return
	if args.size() != 2:
		push_error("Usage: -- <telemetry JSONL file or directory> <report directory>")
		quit(2)
		return
	var paths: PackedStringArray = []
	if FileAccess.file_exists(args[0]): paths.append(args[0])
	else:
		var directory: DirAccess = DirAccess.open(args[0])
		if directory == null:
			quit(2)
			return
		for name: String in directory.get_files():
			if name.ends_with(".jsonl"): paths.append(args[0].path_join(name))
	paths.sort()
	var report: TelemetryReport = TelemetryReport.new()
	for path: String in paths:
		var reader: TelemetryReader = TelemetryReader.new()
		report.add(reader.read_file(path), reader.error)
	if not report.write(args[1]):
		push_error(report.error)
		quit(1)
		return
	print("TELEMETRY_FILES=%d RUNS=%d ERRORS=%d REPORT=%s" % [paths.size(), report.runs.size(), report.errors.size(), ProjectSettings.globalize_path(args[1])])
	quit(0 if report.errors.is_empty() else 1)

func _bounded(args: PackedStringArray) -> void:
	if args.size() < 3:
		push_error("Usage: -- --bounded <input> <new output directory> [--max-run-bytes=N --max-line-bytes=N --max-retained-bytes=N --max-observation-events=N --max-seconds=N]")
		quit(2)
		return
	var job: BOUNDED = BOUNDED.new()
	var options: Dictionary[String, String] = {"--max-run-bytes": "maximum_run_bytes", "--max-line-bytes": "maximum_line_bytes", "--max-retained-bytes": "maximum_retained_bytes", "--max-observation-events": "maximum_observation_events", "--max-seconds": "maximum_elapsed_ms"}
	for index: int in range(3, args.size()):
		var key: String = args[index].get_slice("=", 0)
		var value: String = args[index].get_slice("=", 1)
		if args[index].count("=") != 1 or not options.has(key) or not value.is_valid_int() or str(value.to_int()) != value or value.to_int() <= 0 or value.to_int() > 2147483647:
			push_error("Invalid bounded analysis option: " + args[index])
			quit(2)
			return
		job.set(options[key], value.to_int() * (1000 if key == "--max-seconds" else 1))
	var paths: Array[String] = []
	if FileAccess.file_exists(args[1]): paths.append(args[1])
	else:
		var directory: DirAccess = DirAccess.open(args[1])
		if directory != null:
			for name: String in directory.get_files():
				if name.ends_with(".jsonl"): paths.append(args[1].path_join(name))
	var success: bool = job.analyze(paths, args[2])
	print("BOUNDED_FILES=%d RUNS=%d ERROR=%s REPORT=%s" % [paths.size(), job.result.get("runs", 0), job.error, ProjectSettings.globalize_path(args[2])])
	quit(0 if success else 1)
