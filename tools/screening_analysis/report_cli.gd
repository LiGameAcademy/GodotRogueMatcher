extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		push_error("Usage: -- <screening record directory> <new report directory> [observations.json]")
		quit(2)
		return
	var directory: DirAccess = DirAccess.open(args[0])
	if directory == null:
		push_error("Cannot read input directory")
		quit(2)
		return
	var document: Dictionary = {}
	if args.size() == 3:
		var file: FileAccess = FileAccess.open(args[2], FileAccess.READ)
		if file == null:
			push_error("Cannot read observations")
			quit(2)
			return
		var parser: JSON = JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary or parser.data.is_empty():
			push_error("Invalid observations JSON")
			quit(2)
			return
		document = parser.data
	var paths: PackedStringArray = directory.get_files()
	paths.sort()
	var report: ScreeningReport = ScreeningReport.new()
	for path: String in paths:
		if path.ends_with(".jsonl"): report.add(args[0].path_join(path))
	if report.runs.is_empty() and report.diagnostics.is_empty(): report.diagnostics.append({"record": args[0], "severity": "error", "reason": "no_records"})
	if not report.write(args[1], document):
		push_error(report.error)
		quit(1)
		return
	var result: Dictionary = report.build(document)
	var errors: int = result.diagnostics.filter(func(row: Dictionary) -> bool: return row.severity == "error").size()
	print("SCREENING_REPORT runs=%d errors=%d output=%s" % [report.runs.size(), errors, ProjectSettings.globalize_path(args[1])])
	quit(2 if errors > 0 else 0)
