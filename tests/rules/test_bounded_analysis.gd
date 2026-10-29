extends GutTest

## Compares bounded exports with the existing full report using real rule-generated facts.
const BOUNDED: Script = preload("res://tools/telemetry_analysis/bounded_analysis.gd")
var _root: String

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult: return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult: return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)
	func close() -> TelemetryWriteResult: return flush()

func before_each() -> void:
	_root = "user://bounded-analysis/" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root)

func _events(seed_value: int) -> Array[Dictionary]:
	var stage: StageConfig = StageConfig.new()
	stage.targets = [1, 10000]
	stage.pressure_intervals = [4, 4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, stage)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.metadata = {"synthetic": true, "purpose": "bounded analysis regression; no human observations"}
	var projector: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "bounded-test")
	run.recorder.record_appended.connect(projector.observe_record)
	run.recorder.begin(run, "bot", false)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	assert_true(run.execute_command(command).accepted)
	for step: int in range(20):
		if run.state.rewards.active_offer != null: break
		run.advance()
	assert_not_null(run.state.rewards.active_offer)
	assert_true(run.execute_command(RandomLegalBot.new(seed_value).choose(run)).accepted)
	for step: int in range(20):
		if run.state.phase == RunState.Phase.INPUT: break
		run.advance()
	run.recorder.finish(run, "censored", "bounded_probe")
	for event: Dictionary in projector.events: assert_eq(TelemetrySchema.validate(event), "")
	return projector.events.duplicate(true)

func _write(name: String, events: Array[Dictionary], tail: String = "") -> String:
	var path: String = _root.path_join(name + ".jsonl")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	for event: Dictionary in events: file.store_line(JSON.stringify(event))
	if not tail.is_empty(): file.store_line(tail)
	file.close()
	return path

func _reference(paths: Array[String]) -> Dictionary:
	var report: TelemetryReport = TelemetryReport.new()
	for path: String in paths:
		var reader: TelemetryReader = TelemetryReader.new()
		report.add(reader.read_file(path), reader.error)
	return report.summary()

func _equivalent(actual: Dictionary, expected: Dictionary) -> void:
	for key: String in ["runs", "events", "groups", "opportunities"]:
		assert_eq(RunSnapshot.canonical(actual[key]), RunSnapshot.canonical(expected[key]), key)

func test_multiple_runs_duplicate_sources_and_parent_rewards_match_existing_report() -> void:
	var first: Array[Dictionary] = _events(87)
	var restored: Array[Dictionary] = first.duplicate(true)
	for event: Dictionary in restored:
		event.parent_run_id = event.run_id
		event.run_id = "restored-probe"
		event.event_id = event.run_id + ":" + event.telemetry_seq
	var paths: Array[String] = [_write("a", first), _write("b", first), _write("c", restored), _write("d", _events(88))]
	var job: BOUNDED = BOUNDED.new()
	var directory: String = _root.path_join("output")
	assert_true(job.analyze(paths, directory), job.error)
	_equivalent(job.result, _reference(paths))
	assert_eq(job.result.bounded.processed_runs, 3)
	assert_lt(job.result.bounded.retained_observation_events, job.result.events)
	for shard: Dictionary in job.result.bounded.shards:
		var csv: String = FileAccess.get_file_as_string(directory.path_join(shard.path).path_join("events.csv"))
		assert_string_contains(csv, "event_json")
		assert_string_contains(csv, "slots")
	assert_false(job.analyze(paths, directory))
	assert_eq(job.error, "analysis_output_not_empty")

func test_bad_tail_and_conflicting_duplicate_keep_diagnostics_without_doubling_samples() -> void:
	var events: Array[Dictionary] = _events(89)
	var conflict: Array[Dictionary] = events.duplicate(true)
	conflict[1].elapsed_ms = str(conflict[1].elapsed_ms.to_int() + 1)
	var paths: Array[String] = [_write("a", events), _write("b", events, "{broken"), _write("c", conflict)]
	var job: BOUNDED = BOUNDED.new()
	assert_false(job.analyze(paths, _root.path_join("output")))
	var reference: Dictionary = _reference(paths)
	_equivalent(job.result, reference)
	assert_eq(job.result.errors, reference.errors)
	assert_false(job.result.bounded.complete)
	assert_eq(job.result.runs, 1)

func test_input_and_observation_budgets_fail_explicitly_without_partial_run_statistics() -> void:
	var path: String = _write("a", _events(90))
	for budget: String in ["maximum_run_bytes", "maximum_retained_bytes", "maximum_observation_events"]:
		var job: BOUNDED = BOUNDED.new()
		job.set(budget, 1)
		assert_false(job.analyze([path], _root.path_join(budget)))
		assert_false(job.result.bounded.complete)
		assert_eq(job.result.runs, 0)
		assert_false(job.result.errors.is_empty())
		assert_eq(job.result.bounded.processed_runs, 0)
	var empty: BOUNDED = BOUNDED.new()
	assert_false(empty.analyze([], _root.path_join("empty")))
	assert_eq(empty.error, "no_telemetry_files")

func test_prefix_completion_and_version_groups_keep_the_existing_meaning() -> void:
	var events: Array[Dictionary] = _events(91)
	var prefix: Array[Dictionary] = events.slice(0, events.size() - 1)
	var other: Array[Dictionary] = events.duplicate(true)
	for event: Dictionary in other:
		event.run_id = "legacy-observation"
		event.event_id = event.run_id + ":" + event.telemetry_seq
		event.offer_version = "offer-unified-trial-v1"
		if event.event_name == "offer_generated":
			event.payload.offer_rules_version = "offer-unified-trial-v1"
			for row: Dictionary in event.payload.explanations.values(): row.erase("utility_pick")
	var paths: Array[String] = [_write("a", prefix), _write("b", events), _write("c", other)]
	var job: BOUNDED = BOUNDED.new()
	assert_false(job.analyze(paths, _root.path_join("output")), "prefix diagnostic remains visible")
	_equivalent(job.result, _reference(paths))
	assert_eq(job.result.opportunities.pool_audit.complete_rewards, 1)
	assert_eq(job.result.opportunities.pool_audit.legacy_rewards, 1)

func test_line_deadline_and_invalid_header_are_diagnosed_without_overwriting_sources() -> void:
	var path: String = _write("a", _events(92))
	var original_hash: String = FileAccess.get_sha256(path)
	var line_job: BOUNDED = BOUNDED.new()
	line_job.maximum_line_bytes = 64
	assert_false(line_job.analyze([path], _root.path_join("line")))
	assert_eq(line_job.result.errors[0].reason, "telemetry_line_budget_exceeded")
	var invalid: String = _write("invalid", [], "{broken")
	var invalid_job: BOUNDED = BOUNDED.new()
	assert_false(invalid_job.analyze([invalid], _root.path_join("invalid-output")))
	assert_eq(invalid_job.result.errors[0].reason, "invalid_telemetry_header")
	var large: String = _root.path_join("large.jsonl")
	var file: FileAccess = FileAccess.open(large, FileAccess.WRITE)
	file.store_string("\n".repeat(2 * 1024 * 1024))
	file.close()
	var time_job: BOUNDED = BOUNDED.new()
	time_job.maximum_elapsed_ms = 1
	assert_false(time_job.analyze([large], _root.path_join("deadline")))
	assert_eq(time_job.result.errors[0].reason, "analysis_time_budget_exceeded")
	var output_file_job: BOUNDED = BOUNDED.new()
	assert_false(output_file_job.analyze([path], path))
	assert_eq(FileAccess.get_sha256(path), original_hash)

func test_actual_cli_exits_for_success_budget_failure_and_bad_options() -> void:
	var path: String = _write("a", _events(93))
	var cases: Array[Dictionary] = [
		{"name": "ok", "options": [], "exit": 0},
		{"name": "budget", "options": ["--max-run-bytes=1"], "exit": 1},
		{"name": "option", "options": ["--max-run-bytes=-1"], "exit": 2}]
	for scenario: Dictionary in cases:
		var args: PackedStringArray = ["--headless", "--text-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/telemetry_analysis/analysis_cli.gd", "--", "--bounded", ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(_root.path_join(scenario.name))]
		for option: String in scenario.options: args.append(option)
		var output: Array = []
		assert_eq(OS.execute(OS.get_executable_path(), args, output, true), scenario.exit, str(output))

func test_case_distinct_run_ids_and_device_names_cannot_overwrite_another_shard() -> void:
	var original: Array[Dictionary] = _events(94)
	var paths: Array[String] = []
	for id: String in ["Run-A", "run-a", "CON"]:
		var events: Array[Dictionary] = original.duplicate(true)
		for event: Dictionary in events:
			event.run_id = id
			event.event_id = id + ":" + event.telemetry_seq
		paths.append(_write("case-" + str(paths.size()), events))
	var job: BOUNDED = BOUNDED.new()
	var directory: String = _root.path_join("output")
	assert_true(job.analyze(paths, directory), job.error)
	assert_eq(job.result.runs, 3)
	var seen: Array[String] = []
	for shard: Dictionary in job.result.bounded.shards:
		assert_false(seen.has(String(shard.path).to_lower()))
		seen.append(String(shard.path).to_lower())
		var file: FileAccess = FileAccess.open(directory.path_join(shard.path).path_join("events.csv"), FileAccess.READ)
		assert_not_null(file)
		if file == null: continue
		file.get_csv_line()
		assert_eq(file.get_csv_line()[0], shard.run_id)
	_equivalent(job.result, _reference(paths))

func test_retained_budget_charges_final_utf8_manifest_and_shard_rows_exactly() -> void:
	var events: Array[Dictionary] = _events(95)
	var path: String = _write("阈值", events)
	var report: TelemetryReport = TelemetryReport.new()
	report.add(events)
	var baseline: BOUNDED = BOUNDED.new()
	assert_true(baseline.analyze([path], _root.path_join("baseline")), baseline.error)
	var metadata_bytes: int = JSON.stringify({"inputs": baseline.manifest, "shards": baseline.result.bounded.shards, "runs": report.runs, "errors": report.errors}).to_utf8_buffer().size()
	assert_eq(baseline.result.bounded.retained_summary_bytes, metadata_bytes)
	var exact_limit: int = metadata_bytes + baseline.result.bounded.retained_observation_bytes
	var exact: BOUNDED = BOUNDED.new()
	exact.maximum_retained_bytes = exact_limit
	assert_true(exact.analyze([path], _root.path_join("exact")), exact.error)
	assert_eq(exact.result.bounded.retained_summary_bytes + exact.result.bounded.retained_observation_bytes, exact_limit)
	var short: BOUNDED = BOUNDED.new()
	short.maximum_retained_bytes = exact_limit - 1
	assert_false(short.analyze([path], _root.path_join("short")))
	assert_false(short.result.bounded.complete)
