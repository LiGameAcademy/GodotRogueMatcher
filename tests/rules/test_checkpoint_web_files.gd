extends GutTest

## Native checks of the adapter/acknowledgement contract; not browser persistence evidence.
const FILES: Script = preload("res://services/run_checkpoint/checkpoint_web_files.gd")
const BACKEND: Script = preload("res://tests/support/checkpoint_web_backend.gd")

func _normal() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_test", false, "web_adapter_test")
	return run

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())

func test_file_operations_roundtrip_and_reject_paths_outside_the_slot() -> void:
	var backend: BACKEND = BACKEND.new()
	var files: FILES = FILES.new("user://slot", backend)
	assert_true((await files.open()).ok)
	assert_eq(files.write_text("user://slot/primary.json", "original"), OK)
	var digest: String = "original".sha256_text()
	assert_eq(files.copy_verified("user://slot/primary.json", "user://slot/previous.tmp"), OK)
	assert_eq(files.replace("user://slot/previous.tmp", "user://slot/previous.json"), OK)
	assert_eq(files.replace("user://slot/primary.json", "user://slot/primary.json"), OK)
	assert_eq(files.fingerprint("user://slot/previous.json"), digest)
	assert_eq(files.write_text("user://slot/../primary.json", "bad"), ERR_INVALID_PARAMETER)
	assert_eq(files.write_text("user://other/primary.json", "bad"), ERR_INVALID_PARAMETER)
	assert_eq(files.write_text("user://slot/checkpoint.tmp", ""), OK)
	assert_eq(backend.writes, 0)
	assert_true((await files.sync()).ok)
	var reopened: FILES = FILES.new("user://slot", backend)
	assert_true((await reopened.open()).ok)
	assert_eq(reopened.read_text("user://slot/primary.json").text, "original")
	assert_eq(reopened.fingerprint("user://slot/previous.json"), digest)
	assert_true(reopened.exists("user://slot/checkpoint.tmp"))
	assert_eq(reopened.read_text("user://slot/checkpoint.tmp").text, "")

func test_failed_browser_commit_restores_exact_acknowledged_pair_and_retry_can_save() -> void:
	var backend: BACKEND = BACKEND.new()
	var files: FILES = FILES.new("user://slot", backend)
	await files.open()
	files.write_text("user://slot/primary.json", "old-primary")
	files.write_text("user://slot/previous.json", "old-previous")
	await files.sync()
	var original: String = backend.image
	backend.fail_write = true
	files.write_text("user://slot/primary.json", "uncommitted")
	assert_false((await files.sync()).ok)
	assert_eq(backend.image, original)
	assert_eq(files.read_text("user://slot/primary.json").text, "old-primary")
	assert_eq(files.read_text("user://slot/previous.json").text, "old-previous")
	backend.fail_write = false
	files.write_text("user://slot/primary.json", "retry")
	assert_true((await files.sync()).ok)
	var reopened: FILES = FILES.new("user://slot", backend)
	await reopened.open()
	assert_eq(reopened.read_text("user://slot/primary.json").text, "retry")

func test_bad_unknown_or_escaping_snapshots_are_not_reset_or_overwritten() -> void:
	for snapshot: Dictionary in [{"schema": "future", "files": {}}, {"schema": FILES.SCHEMA, "files": {"../primary.json": ""}},
		{"schema": FILES.SCHEMA, "files": {"primary.json": "AA"}}, {"schema": FILES.SCHEMA, "files": {}, "extra": true}]:
		var backend: BACKEND = BACKEND.new()
		backend.image = JSON.stringify(snapshot)
		var original: String = backend.image
		var files: FILES = FILES.new("user://slot", backend)
		assert_false((await files.open()).ok)
		assert_false(files.ready)
		assert_eq(files.write_text("user://slot/primary.json", "replacement"), ERR_UNAVAILABLE)
		assert_false((await files.sync()).ok)
		assert_eq(backend.image, original)
		assert_eq(backend.writes, 0)

func test_raw_corrupt_original_bytes_survive_copy_and_database_roundtrip() -> void:
	var backend: BACKEND = BACKEND.new()
	backend.image = JSON.stringify({"schema": FILES.SCHEMA, "files": {"primary.json": Marshalls.raw_to_base64(PackedByteArray([0, 255, 128]))}})
	var files: FILES = FILES.new("user://slot", backend)
	await files.open()
	var digest: String = files.fingerprint("user://slot/primary.json")
	var copy: String = "user://slot/primary.json.corrupt-" + digest + ".json"
	assert_eq(files.copy_verified("user://slot/primary.json", copy), OK)
	assert_eq(files.fingerprint(copy), digest)
	await files.sync()
	var reopened: FILES = FILES.new("user://slot", backend)
	await reopened.open()
	assert_eq(reopened.fingerprint(copy), digest)
	assert_eq((JSON.parse_string(backend.image) as Dictionary).files[copy.get_file()], Marshalls.raw_to_base64(PackedByteArray([0, 255, 128])))

func test_conflicting_writer_requires_reload_instead_of_reusing_stale_local_files() -> void:
	var backend: BACKEND = BACKEND.new()
	var files: FILES = FILES.new("user://slot", backend)
	await files.open()
	files.write_text("user://slot/primary.json", "old-local")
	await files.sync()
	backend.image = JSON.stringify({"schema": FILES.SCHEMA, "files": {"primary.json": Marshalls.raw_to_base64("other-tab".to_utf8_buffer())}})
	var remote: String = backend.image
	backend.fail_write = true
	backend.failure_reason = "web_storage_conflict"
	files.write_text("user://slot/primary.json", "stale-overwrite")
	assert_eq((await files.sync()).reason, "web_storage_conflict")
	assert_false(files.ready)
	assert_false(files.read_text("user://slot/primary.json").ok)
	assert_eq(files.write_text("user://slot/primary.json", "retry-stale"), ERR_UNAVAILABLE)
	assert_eq(backend.image, remote)

func test_no_thread_job_waits_for_actual_commit_and_keeps_single_ownership() -> void:
	var backend: BACKEND = BACKEND.new()
	backend.hold = true
	var files: FILES = FILES.new("user://slot", backend)
	await files.open()
	var run: RunController = _normal()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	var store: CheckpointStore = CheckpointStore.new("user://slot", files)
	var job: CheckpointJob = CheckpointJob.new()
	job.use_threads = false
	assert_eq(job.start_save(store, encoded, 10000000), OK)
	assert_false(job.is_done())
	assert_true(await _wait(func() -> bool: return backend.writing))
	assert_null(job.get("_thread"))
	assert_false(job.is_done())
	assert_eq(job.finish().reason, "job_not_done")
	assert_eq(store.inspect_latest().reason, "busy", "the Store also retains ownership during acknowledgement")
	assert_eq(job.start_load(store, encoded.manifest, 10000000), ERR_BUSY)
	var before: FILES = FILES.new("user://slot", backend)
	await before.open()
	assert_false(CheckpointStore.new("user://slot", before).inspect_latest().ok)
	backend.release_write.emit()
	assert_true(await _wait(job.is_done))
	assert_true(job.finish().ok)
	var reopened: FILES = FILES.new("user://slot", backend)
	await reopened.open()
	var loaded: Dictionary = RunCheckpointSession.new(CheckpointStore.new("user://slot", reopened), encoded.manifest).load_candidate()
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok: assert_eq(RunSnapshot.capture(loaded.run), RunSnapshot.capture(run))

func test_failed_invalidation_is_not_durable_and_retry_prevents_both_generations() -> void:
	var backend: BACKEND = BACKEND.new()
	var files: FILES = FILES.new("user://slot", backend)
	await files.open()
	var run: RunController = _normal()
	var store: CheckpointStore = CheckpointStore.new("user://slot", files)
	var session: RunCheckpointSession = RunCheckpointSession.new(store, RunCheckpointCodec.manifest(run))
	assert_true(session.save(run).ok)
	assert_true((await store.sync()).ok)
	var original: String = backend.image
	backend.fail_write = true
	assert_true(store.invalidate(run.state.run_id, "terminal").ok, "local file operation is not yet durable")
	assert_false((await store.sync()).ok)
	assert_eq(backend.image, original)
	var old: FILES = FILES.new("user://slot", backend)
	await old.open()
	assert_true(CheckpointStore.new("user://slot", old).inspect_latest().ok, "unacknowledged invalidation must not pretend persistence")
	backend.fail_write = false
	assert_true(store.invalidate(run.state.run_id, "terminal").ok)
	assert_true((await store.sync()).ok)
	var reopened: FILES = FILES.new("user://slot", backend)
	await reopened.open()
	assert_eq(CheckpointStore.new("user://slot", reopened).inspect_latest().reason, "run_invalidated")

func test_failed_sync_revokes_completed_ticket_instead_of_false_duplicate_success() -> void:
	var backend: BACKEND = BACKEND.new()
	var files: FILES = FILES.new("user://slot", backend)
	await files.open()
	var run: RunController = _normal()
	var store: CheckpointStore = CheckpointStore.new("user://slot", files)
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	assert_true(store.begin_run(run.state.run_id).ok)
	var ticket: int = store.stage({"probe": "unacknowledged"}, policy)
	assert_true(store.commit(ticket).ok)
	backend.fail_write = true
	assert_false((await store.sync()).ok)
	assert_false(store.commit(ticket).ok, "a rolled-back browser commit cannot be a successful duplicate")
	backend.fail_write = false
	assert_true(store.begin_run(run.state.run_id).ok)
	var next: int = store.stage({"probe": "restaged"}, policy)
	assert_true(store.commit(next).ok)
	assert_true((await store.sync()).ok)
	assert_true(store.commit(next).ok, "acknowledged duplicate remains idempotent")
