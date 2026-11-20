extends GutTest

## Desktop worker isolation and live main-loop progress while frozen values are validated.
var _directories: Array[String] = []

func after_each() -> void:
	for directory: String in _directories:
		if not DirAccess.dir_exists_absolute(directory): continue
		for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
		DirAccess.remove_absolute(directory)
	_directories.clear()

func _store() -> CheckpointStore:
	var directory: String = "user://checkpoint-job-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.append(directory)
	return CheckpointStore.new(directory)

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_job_test", false)
	return run

func _join(job: CheckpointJob) -> Dictionary:
	var frames: int = 0
	var deadline: int = Time.get_ticks_msec() + 15000
	while not job.is_done() and Time.get_ticks_msec() < deadline:
		frames += 1
		await get_tree().process_frame
	assert_true(job.is_done(), "worker must finish within this desktop test limit")
	assert_gt(frames, 0, "main loop progressed while worker was active")
	return job.finish()

func test_frozen_save_does_not_read_a_live_run_and_load_returns_an_isolated_candidate() -> void:
	var run: RunController = _run()
	var original: Dictionary = RunSnapshot.capture(run)
	var config_before: String = RunSnapshot.digest(RunSnapshot.config(run))
	var global_run: RunController = GameManager.run
	var store: CheckpointStore = _store()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	var job: CheckpointJob = CheckpointJob.new()
	assert_eq(job.start_save(store, encoded, 10000000), OK)
	var command: RunCommand = RandomLegalBot.new(1).choose(run)
	assert_true(run.execute_command(command).accepted)
	var saved: Dictionary = await _join(job)
	assert_true(saved.ok, saved.reason)
	assert_eq(job.start_load(store, encoded.manifest, 10000000), OK)
	var loaded: Dictionary = await _join(job)
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	assert_eq(RunSnapshot.capture(loaded.run), original)
	assert_ne(RunSnapshot.capture(run), original)
	assert_ne(loaded.run, run)
	assert_eq(loaded.run.recorder.path, "")
	assert_same(GameManager.run, global_run)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config_before)

func test_inspection_checks_invalidation_and_never_constructs_a_run() -> void:
	var store: CheckpointStore = _store()
	var run: RunController = _run()
	assert_true(RunCheckpointSession.new(store, RunCheckpointCodec.manifest(run)).save(run).ok)
	var metadata: Dictionary = store.inspect_latest()
	assert_true(metadata.ok, metadata.reason)
	assert_eq(metadata.run_id, run.state.run_id)
	assert_false(metadata.has("record"))
	assert_false(metadata.has("payload"))
	assert_eq(metadata.manifest, RunCheckpointCodec.manifest(run))
	assert_true(store.invalidate(run.state.run_id, "abandoned").ok)
	assert_eq(store.inspect_latest().reason, "run_invalidated")

func test_incremental_history_is_read_only_and_remains_independent_of_the_source() -> void:
	var run: RunController = _run()
	var cache: CheckpointHistory = CheckpointHistory.new()
	var first: Dictionary = cache.freeze(run)
	assert_true(first.ok, first.reason)
	assert_true(first.payload.records.is_read_only())
	assert_true(first.payload.records[0].is_read_only())
	assert_true(first.payload.records[0].config.skills.is_read_only())
	var original: Dictionary = first.payload.state.duplicate(true)
	run.recorder.records[0].metadata["test_annotation"] = "new"
	assert_false(first.payload.records[0].metadata.has("test_annotation"))
	var second: Dictionary = cache.freeze(run)
	assert_eq(second.payload.records[0].metadata.test_annotation, "new")
	assert_eq(first.payload.state, original)
	var job: CheckpointJob = CheckpointJob.new()
	var store: CheckpointStore = _store()
	assert_eq(job.start_save(store, second, 10000000), OK)
	var saved: Dictionary = await _join(job)
	assert_true(saved.ok, saved.reason)
	assert_eq(job.start_load(store, second.manifest, 10000000), OK)
	var loaded: Dictionary = await _join(job)
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok:
		var from_worker: Dictionary = (loaded.history as CheckpointHistory).freeze(loaded.run)
		assert_true(from_worker.ok, from_worker.reason)
		assert_eq(from_worker.payload.state, original)
