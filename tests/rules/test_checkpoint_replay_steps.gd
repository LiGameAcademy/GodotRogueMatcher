extends GutTest

var _directory: String = ""

func after_each() -> void:
	if _directory.is_empty(): return
	for name: String in DirAccess.get_files_at(_directory): DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	_directory = ""

func test_single_thread_job_yields_and_restores_without_reading_live_changes() -> void:
	var source: RuleReplay = RuleReplay.new()
	assert_true(source.restore_prefix(_records()), source.error)
	var before: Dictionary = RunSnapshot.capture(source.run)
	var encoded: Dictionary = RunCheckpointCodec.encode(source.run)
	_directory = "user://checkpoint-step-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store: CheckpointStore = CheckpointStore.new(_directory)
	var job: CheckpointJob = CheckpointJob.new()
	job.use_threads = false
	assert_eq(job.start_save(store, encoded, 10000000), OK)
	assert_eq(job.finish().reason, "job_not_done")
	assert_eq(job.start_load(store, encoded.manifest, 10000000), ERR_BUSY)
	assert_true(source.run.execute_command(GreedyBot.new(7).choose(source.run)).accepted)
	var frames: int = 0
	while not job.is_done() and frames < 1000:
		await get_tree().process_frame
		frames += 1
	assert_true(job.is_done())
	assert_gt(frames, 5, "actual replay spans frames")
	assert_null(job.get("_thread"))
	var saved: Dictionary = job.finish()
	assert_true(saved.ok, saved.reason)
	assert_eq(job.start_load(store, encoded.manifest, 10000000), OK)
	frames = 0
	while not job.is_done() and frames < 1000:
		await get_tree().process_frame
		frames += 1
	assert_true(job.is_done())
	assert_gt(frames, 5)
	var loaded: Dictionary = job.finish()
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok: assert_eq(RunSnapshot.capture(loaded.run), before)
	assert_ne(RunSnapshot.capture(source.run), before)

func test_chunked_prefix_matches_synchronous_frozen_endpoint() -> void:
	var records: Array[Dictionary] = _records()
	var baseline: RuleReplay = RuleReplay.new()
	assert_true(baseline.restore_prefix(records), baseline.error)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.has_method("start_prefix"), "bounded replay entry must exist")
	if not replay.has_method("start_prefix"): return
	assert_true(replay.call("start_prefix", records))
	var steps: int = 0
	var result: Dictionary = {"done": false}
	while not result.done and steps < records.size():
		var before: int = replay.checked_records
		result = replay.call("step_prefix", 2, 1000000)
		assert_true(result.ok, replay.error)
		assert_lte(replay.checked_records - before, 3)
		steps += 1
	assert_true(result.done)
	assert_gt(steps, 10)
	assert_eq(RunSnapshot.capture(replay.run), RunSnapshot.capture(baseline.run))
	assert_eq(replay.run.continuation, baseline.run.continuation)
	assert_eq(replay.run.recorder.records.size(), baseline.run.recorder.records.size())
	for index: int in range(baseline.run.recorder.records.size()):
		var actual: Dictionary = replay.run.recorder.records[index].duplicate(true)
		var expected: Dictionary = baseline.run.recorder.records[index].duplicate(true)
		actual.erase("elapsed_ms")
		expected.erase("elapsed_ms")
		assert_eq(actual, expected)
	assert_false(replay.complete, "safe prefix never becomes completed replay")

func test_late_invalid_record_is_rejected_after_earlier_steps() -> void:
	var records: Array[Dictionary] = _records()
	records.back().seq = "999"
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.has_method("start_prefix"), "bounded replay entry must exist")
	if not replay.has_method("start_prefix"): return
	assert_true(replay.call("start_prefix", records))
	var result: Dictionary = {"done": false}
	var steps: int = 0
	while not result.done and steps < records.size():
		result = replay.call("step_prefix", 3, 1000000)
		steps += 1
	assert_true(result.done)
	assert_false(result.ok)
	assert_string_contains(replay.error, "invalid_sequence")
	assert_false(replay.complete)

func test_failed_step_can_restart_but_completed_prefix_cannot_step_again() -> void:
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.start_prefix(_records()))
	var invalid: Dictionary = replay.step_prefix(0, 1000)
	assert_false(invalid.ok)
	assert_true(invalid.done)
	assert_eq(invalid.reason, "invalid_step_budget")
	assert_true(replay.start_prefix(_records()))
	assert_eq(replay.error, "")
	var completed: Dictionary = replay.step_prefix(1000, 10000000)
	assert_true(completed.ok, replay.error)
	assert_true(completed.done)
	assert_eq(replay.step_prefix().reason, "replay_not_started")
	assert_false(replay.complete)

func _records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	records.assign(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/checkpoint_decimal_roundtrip.json")))
	return records

func test_sliced_validation_rejects_the_same_malformed_prefixes_and_depths() -> void:
	var source: RuleReplay = RuleReplay.new()
	assert_true(source.restore_prefix(_records()), source.error)
	if source.run == null: return
	var encoded: Dictionary = RunCheckpointCodec.encode(source.run)
	assert_true(encoded.ok, encoded.reason)
	if not encoded.ok: return
	var cases: Array[Dictionary] = []
	var bad: Dictionary = encoded.payload.duplicate(true)
	var mixed: Array = []
	for row: Dictionary in bad.records: mixed.append(row)
	mixed[10] = "not_a_record"
	bad.records = mixed
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.records.back().seq = "999"
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.records[10].kind = "FutureRecord"
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.schema = "future_prefix"
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.records.resize(RunCheckpointCodec.MAX_RECORDS + 1)
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.records = []
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.records = "not_an_array"
	cases.append(bad)
	bad = encoded.payload.duplicate(true)
	bad.records[10]["number"] = 1
	cases.append(bad)
	for wraps: int in [60, 61]:
		var leaf: Dictionary = {"value": 0.75}
		for index: int in range(wraps): leaf = {"next": leaf}
		bad = encoded.payload.duplicate(true)
		bad.records[10]["extra"] = leaf
		cases.append(bad)
	var cycle: Dictionary = {}
	cycle["self"] = cycle
	bad = encoded.payload.duplicate(true)
	bad.records[10]["extra"] = cycle
	cases.append(bad)
	for value: Dictionary in cases:
		var baseline: Dictionary = RunCheckpointCodec.decode(value, encoded.manifest, 10000000)
		var sliced: Dictionary = await RunCheckpointCodec.decode_sliced(value, encoded.manifest, 10000000, false, _yield_validation_frame)
		assert_false(baseline.ok)
		assert_eq(sliced.reason, baseline.reason)
	cycle.clear()
	var limited: Dictionary = await RunCheckpointCodec.decode_sliced(encoded.payload, encoded.manifest, 1, false, _yield_validation_frame)
	assert_false(limited.ok)
	assert_eq(limited.reason, "rebuild_budget_exceeded")

func _yield_validation_frame() -> void:
	await get_tree().process_frame

func test_sliced_size_check_matches_exact_json_limit_with_unicode_and_escapes() -> void:
	var source: RuleReplay = RuleReplay.new()
	assert_true(source.restore_prefix(_records()), source.error)
	if source.run == null: return
	var encoded: Dictionary = RunCheckpointCodec.encode(source.run)
	var payload: Dictionary = encoded.payload
	payload.records[10]["escaped"] = "中文\"\\\n\t".repeat(7)
	payload.records[10]["padding"] = ""
	var remaining: int = RunCheckpointCodec.MAX_PAYLOAD_BYTES - JSON.stringify(payload).to_utf8_buffer().size()
	payload.records[10].padding = "x".repeat(remaining)
	assert_eq(JSON.stringify(payload).to_utf8_buffer().size(), RunCheckpointCodec.MAX_PAYLOAD_BYTES)
	for extra: String in ["", "x"]:
		payload.records[10].padding += extra
		var baseline: String = RunCheckpointCodec._payload_error(payload)
		var checked: Dictionary = await RunCheckpointCodec._payload_error_sliced(payload, _yield_validation_frame, Time.get_ticks_usec(), 10000000)
		assert_eq(checked.reason, baseline)
		assert_eq(checked.reason, "" if extra.is_empty() else "payload_size_limit")
