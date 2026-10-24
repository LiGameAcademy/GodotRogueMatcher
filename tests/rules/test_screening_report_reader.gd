extends GutTest

const ROOT: String = "res://docs/evidence/issue119-screening/"
var directory: String

func before_each() -> void:
	directory = "user://screening_report_tests/%s" % str(Time.get_ticks_usec())
	assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)

func _copy(name: String, sidecar: bool = false) -> String:
	var path: String = directory.path_join(name + ".jsonl")
	assert_eq(DirAccess.copy_absolute(ROOT + name + ".jsonl", path), OK)
	if sidecar: assert_eq(DirAccess.copy_absolute(ROOT + name + "-screening.json", path.get_basename() + "-screening.json"), OK)
	return path

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func test_real_ui_record_has_deduplicated_nine_cells_and_unknown_human_fields() -> void:
	var reader: ScreeningRecordReader = ScreeningRecordReader.new()
	var row: Dictionary = reader.read(ROOT + "ui-t-overlap.jsonl")
	assert_eq(reader.error, "")
	assert_eq(row.score, 126)
	assert_eq(row.source_kind, "human_unobserved")
	assert_true(row.window_complete)
	assert_eq(row.metrics.match_events, 1)
	assert_eq(row.metrics.shape_event_counts.t, 1)
	assert_eq(row.metrics.shape_event_counts.line, 1)
	assert_eq(row.metrics.removed_unique_entities, 9)
	assert_eq(row.metrics.births_in_window, 0)
	assert_eq(row.metrics.by_source.direct_move.removed, 9)
	assert_eq(row.metrics.net_empty_cells, 9)
	for value: Variant in row.human.values(): assert_null(value)

func test_six_bot_windows_remain_automated_and_zero_score_is_observed_not_failure() -> void:
	for key: String in ScreeningDeck.CONFIGS:
		var reader: ScreeningRecordReader = ScreeningRecordReader.new()
		var row: Dictionary = reader.read(ROOT + "free-" + key + ".jsonl")
		assert_eq(reader.error, "")
		assert_eq(row.source_kind, "automated")
		assert_eq(row.actions, 15)
		assert_true(row.window_complete)
		assert_eq(row.score, 0)
		assert_eq(row.metrics.match_events, 0)
		assert_eq(row.metrics.births_in_window, 45)
		assert_eq(row.metrics.net_empty_cells, -45)
		assert_null(row.elapsed_ms)
		assert_null(row.human.prediction_correct)

func test_wrong_task_records_births_separately_from_matches() -> void:
	var row: Dictionary = ScreeningRecordReader.new().read(ROOT + "t-wrong.jsonl")
	assert_eq(row.score, 0)
	assert_eq(row.metrics.match_events, 0)
	assert_eq(row.metrics.births_in_window, 3)
	assert_eq(row.metrics.removed_unique_entities, 0)
	assert_eq(row.metrics.net_empty_cells, -3)
	assert_eq(row.metrics.births_by_source.normal, 3)

func test_incomplete_tampered_and_non_screening_records_are_not_scored_as_zero() -> void:
	var path: String = _copy("t-direct")
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	lines.remove_at(lines.size() - 1)
	_write(path, "\n".join(lines) + "\n")
	var reader: ScreeningRecordReader = ScreeningRecordReader.new()
	assert_true(reader.read(path).is_empty())
	assert_false(reader.error.is_empty())
	path = _copy("t-direct")
	lines = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var footer: Dictionary = JSON.parse_string(lines[-1]) as Dictionary
	footer.score = "999999"
	lines[-1] = JSON.stringify(footer)
	_write(path, "\n".join(lines) + "\n")
	assert_true(reader.read(path).is_empty())
	assert_false(reader.error.is_empty())
	assert_true(reader.read("res://docs/evidence/issue118-square/square-unlock-record.jsonl").is_empty())
	assert_eq(reader.error, "not_screening_record")

func test_sidecar_conflicts_and_invalid_metadata_are_explicit_errors() -> void:
	var path: String = _copy("ui-t-overlap", true)
	var side: String = path.get_basename() + "-screening.json"
	var value: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(side)) as Dictionary
	value.actions = 999
	_write(side, JSON.stringify(value))
	var reader: ScreeningRecordReader = ScreeningRecordReader.new()
	assert_true(reader.read(path).is_empty())
	assert_eq(reader.error, "sidecar_actions_mismatch")
	value.actions = 1
	value.run_id = "other"
	_write(side, JSON.stringify(value))
	assert_true(reader.read(path).is_empty())
	assert_eq(reader.error, "sidecar_identity_mismatch")
	path = _copy("t-direct")
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var header: Dictionary = JSON.parse_string(lines[0]) as Dictionary
	header.metadata = []
	lines[0] = JSON.stringify(header)
	_write(path, "\n".join(lines) + "\n")
	assert_true(reader.read(path).is_empty())
	assert_eq(reader.error, "invalid_metadata")

func test_shortened_ui_windows_are_not_claimed_as_formal_fifteen_or_eight_minutes() -> void:
	var action: Dictionary = ScreeningRecordReader.new().read(ROOT + "ui-action-limit.jsonl")
	assert_false(action.window_complete)
	var time: Dictionary = ScreeningRecordReader.new().read(ROOT + "ui-time-paused.jsonl")
	assert_false(time.window_complete)
	var path: String = _copy("ui-time-paused")
	var missing: Dictionary = ScreeningRecordReader.new().read(path)
	assert_null(missing.window_complete)
	assert_null(missing.elapsed_ms)

func test_identical_copies_are_counted_once_and_conflicting_ids_quarantine_all_copies() -> void:
	var report: ScreeningReport = ScreeningReport.new()
	var path: String = _copy("t-direct")
	report.add(ROOT + "t-direct.jsonl")
	report.add(path)
	assert_eq(report.runs.size(), 1)
	assert_eq(report.duplicate_files, 1)
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var header: Dictionary = JSON.parse_string(lines[0]) as Dictionary
	header.build = "different-build"
	lines[0] = JSON.stringify(header)
	_write(path, "\n".join(lines) + "\n")
	report.add(path)
	assert_eq(report.runs.size(), 0)
	assert_eq(report.diagnostics.back().reason, "conflicting_duplicate_run")
	report.add(ROOT + "t-direct.jsonl")
	assert_eq(report.runs.size(), 0)

func test_event_projections_do_not_double_count_shared_entities_or_repeated_event_ids() -> void:
	var replay: RuleReplay = RuleReplay.new()
	var rows: Array[Dictionary] = replay.read_file(ROOT + "t-overlap.jsonl")
	for row: Dictionary in rows:
		if row.kind == "RuleResult" and not row.events.is_empty(): row.events.append(row.events[0].duplicate(true))
	var result: Dictionary = ScreeningRecordReader._metrics(rows)
	assert_eq(result.match_events, 1)
	assert_eq(result.removed_unique_entities, 9)
	assert_eq(result.by_source.direct_move.score, 126)

func test_writer_preserves_inputs_existing_output_and_does_not_retain_high_scores() -> void:
	var report: ScreeningReport = ScreeningReport.new()
	report.add(ROOT + "ui-t-overlap.jsonl")
	var before: String = FileAccess.get_sha256(ROOT + "ui-t-overlap.jsonl")
	var output: String = directory.path_join("report")
	assert_true(report.write(output), report.error)
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("screening-report.json"))) as Dictionary
	for row: Dictionary in content.configurations: assert_null(row.screening_decision)
	assert_true(content.fixed_task_accuracy.is_empty())
	assert_false(report.write(output))
	assert_true(report.error.begins_with("output_exists:"))
	assert_eq(FileAccess.get_sha256(ROOT + "ui-t-overlap.jsonl"), before)
	assert_eq(content.runs[0].human, ScreeningRecordReader.blank_human())

func test_replayable_missing_or_modified_geometry_cannot_impersonate_a_versioned_config() -> void:
	for fixed: bool in [true, false]:
		var templates: Array[MatchShapeTemplate] = []
		if not fixed:
			var changed: MatchShapeTemplate = ScreeningDeck.config("l").template.duplicate(true) as MatchShapeTemplate
			changed.offsets[0] = Vector2i(2, 0)
			templates.append(changed)
		var profile: StringName = RunController.SCREENING_FIXED_PROFILE if fixed else RunController.SCREENING_PROFILE
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), 119, null, profile)
		run.initialize("screening_l_direct" if fixed else "normal")
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "screening_automated_fixture", true, "development", directory)
		run.recorder.finish(run, "censored", "geometry_probe")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(run.recorder.path), replay.error)
		var reader: ScreeningRecordReader = ScreeningRecordReader.new()
		assert_true(reader.read(run.recorder.path).is_empty())
		assert_eq(reader.error, "configuration_geometry_mismatch")
