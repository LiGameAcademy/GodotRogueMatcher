extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
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
