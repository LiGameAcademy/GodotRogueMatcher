extends GutTest

var directory: String
var source: String

func before_each() -> void:
	directory = "user://screening_cli_tests/%s" % str(Time.get_ticks_usec())
	source = directory.path_join("source")
	assert_eq(DirAccess.make_dir_recursive_absolute(source), OK)
	for name: String in ["ui-t-overlap.jsonl", "ui-t-overlap-screening.json"]:
		assert_eq(DirAccess.copy_absolute("res://docs/evidence/issue119-screening/" + name, source.path_join(name)), OK)

func _invoke(input: String, output: String, notes: String = "") -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/screening_analysis/report_cli.gd", "--", input, output]
	if not notes.is_empty(): args.append(notes)
	var captured: Array = []
	return OS.execute(OS.get_executable_path(), args, captured, true)

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func test_actual_cli_writes_report_and_blank_template_without_modifying_sources() -> void:
	var output: String = directory.path_join("result")
	var before: String = FileAccess.get_sha256(source.path_join("ui-t-overlap.jsonl"))
	assert_eq(_invoke(source, output), 0)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("screening-report.json"))) as Dictionary
	assert_eq(report.runs.size(), 1)
	assert_null(report.runs[0].human.participant)
	for row: Dictionary in report.configurations: assert_null(row.screening_decision)
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("observations-template.json"))) as Dictionary
	assert_null(template.observations[0].prediction_correct)
	assert_eq(FileAccess.get_sha256(source.path_join("ui-t-overlap.jsonl")), before)
	assert_eq(_invoke(source, output), 1)
	assert_eq(FileAccess.get_sha256(source.path_join("ui-t-overlap.jsonl")), before)

func test_actual_cli_keeps_valid_records_and_reports_damaged_input_with_nonzero_exit() -> void:
	_write(source.path_join("broken.jsonl"), "not JSON\n")
	var output: String = directory.path_join("partial")
	assert_eq(_invoke(source, output), 2)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("screening-report.json"))) as Dictionary
	assert_eq(report.runs.size(), 1)
	assert_eq(report.diagnostics.size(), 1)
	assert_eq(report.diagnostics[0].severity, "error")

func test_actual_cli_rejects_empty_or_malformed_manual_input_instead_of_silently_ignoring_it() -> void:
	var notes: String = directory.path_join("notes.json")
	_write(notes, "{}")
	assert_eq(_invoke(source, directory.path_join("empty-notes"), notes), 2)
	assert_false(FileAccess.file_exists(directory.path_join("empty-notes/screening-report.json")))
	_write(notes, "{oops")
	assert_eq(_invoke(source, directory.path_join("broken-notes"), notes), 2)
	assert_eq(FileAccess.get_file_as_string(notes), "{oops")

func test_actual_cli_rejects_unknown_human_ids_and_empty_directories() -> void:
	var notes: String = directory.path_join("notes.json")
	_write(notes, JSON.stringify({"schema": "screening-observations-v1", "observations": [{"run_id": "unknown"}], "decisions": []}))
	var output: String = directory.path_join("bad-id")
	assert_eq(_invoke(source, output, notes), 2)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("screening-report.json"))) as Dictionary
	assert_null(report.runs[0].human.participant)
	var empty: String = directory.path_join("empty-source")
	assert_eq(DirAccess.make_dir_recursive_absolute(empty), OK)
	assert_eq(_invoke(empty, directory.path_join("empty-result")), 2)
