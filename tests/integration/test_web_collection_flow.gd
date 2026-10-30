extends GutTest

const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
const PERSISTENCE: Script = preload("res://tests/support/web_telemetry_persistence.gd")
const SUPPORT: Script = preload("res://services/telemetry/web_collection_support.gd")
var _collection: RunCollection
var _zip_path: String = ""

func after_each() -> void:
	if is_instance_valid(_collection): _collection.free()
	_collection = null
	if not _zip_path.is_empty(): DirAccess.remove_absolute(_zip_path)
	_zip_path = ""

func test_refresh_lineage_uses_acknowledged_parent_and_new_segment_without_new_start() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	var backend: BACKEND = BACKEND.new(persistence)
	var support: SUPPORT = SUPPORT.new(backend)
	assert_true((await support.open()).ok)
	_collection = RunCollection.new()
	_collection.set("_web", support)
	add_child(_collection)
	var factory: TelemetryFactory = TelemetryFactory.new("s-web-parent")
	factory.sink_factory = support.make_sink
	_collection.configure("web_playtest", factory, false)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", false, "web_flow_test")
	_collection.bind(run)
	assert_true(await _wait(func() -> bool: return not support.pending()))
	var trace: Dictionary = _collection.checkpoint_trace(run)
	assert_eq(trace.accepted_seq, trace.persisted_seq)
	var source_name: String = "telemetry/" + run.state.run_id + ".jsonl"
	var source_text: String = backend.files()[source_name]
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(run.recorder.records), replay.error)
	var before: Dictionary = RunSnapshot.capture(replay.run)
	var checkpoint: Dictionary = {"checkpoint_id": "web-test-point", "trace": trace, "prepared": {"session_id": "s-web-child", "record_file": false}}
	var projector: TelemetryProjector = _collection.resume("web_playtest", replay.run, checkpoint, false)
	assert_eq(projector.events[0].event_name, "run_resumed")
	assert_true(projector.events[0].resume.lineage_known)
	assert_eq(projector.events[0].resume.parent_segment_id, "s-web-parent")
	assert_eq(RunSnapshot.capture(replay.run), before)
	_collection.suspend_for_checkpoint()
	assert_true(await _wait(func() -> bool: return not support.pending()))
	assert_eq(backend.files()[source_name], source_text, "old observation prefix is never rewritten")
	var starts: int = 0
	var resumes: int = 0
	var closes: int = 0
	var endings: int = 0
	var ids: Dictionary[String, bool] = {}
	for name: String in backend.files():
		if not name.begins_with("telemetry/"): continue
		var reader: TelemetryReader = TelemetryReader.new()
		var events: Array[Dictionary] = reader.read_text(backend.files()[name])
		assert_true(reader.error in ["", "incomplete_telemetry_no_complete_ending"], reader.error)
		for event: Dictionary in events:
			assert_false(ids.has(event.event_id))
			ids[event.event_id] = true
			starts += int(event.event_name == "run_started")
			resumes += int(event.event_name == "run_resumed")
			closes += int(event.event_name == "resume_segment_closed")
			endings += int(event.event_name == "run_ended")
	assert_eq([starts, resumes, closes, endings], [1, 1, 1, 0])
	var exported: Dictionary = await support.prepare_export()
	assert_true(exported.ok, exported.reason)
	assert_true(support.export_ready)
	_zip_path = "user://web-export-test-%d.zip" % Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(_zip_path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null: return
	file.store_buffer(support.get("_export_bytes"))
	file.close()
	var zip: ZIPReader = ZIPReader.new()
	assert_eq(zip.open(_zip_path), OK)
	assert_eq(zip.read_file(source_name).get_string_from_utf8(), source_text)
	var manifest: Dictionary = JSON.parse_string(zip.read_file("export_manifest.json").get_string_from_utf8())
	assert_eq(manifest.files[source_name].sha256, source_text.sha256_text())
	zip.close()

func test_missing_parent_is_unknown_lineage_without_changing_the_rule_snapshot() -> void:
	var support: SUPPORT = SUPPORT.new(BACKEND.new(PERSISTENCE.new()))
	assert_true((await support.open()).ok)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "human", false, "web_flow_test")
	var before: Dictionary = RunSnapshot.capture(run)
	var result: Dictionary = support.prepare_resume(run, {"checkpoint_id": "missing-parent", "trace": {}}, "web_playtest", "unknown")
	assert_eq(result.trace.status, "parent_prefix_unavailable")
	assert_false(TelemetryResume.header(run, result, "web_playtest", "unknown").metadata.resume.lineage_known)
	assert_eq(RunSnapshot.capture(run), before)

func test_failed_rule_footer_never_publishes_a_complete_natural_ending() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	var backend: BACKEND = BACKEND.new(persistence)
	var support: SUPPORT = SUPPORT.new(backend)
	assert_true((await support.open()).ok)
	_collection = RunCollection.new()
	_collection.set("_web", support)
	add_child(_collection)
	var factory: TelemetryFactory = TelemetryFactory.new("s-web-ending")
	factory.sink_factory = support.make_sink
	_collection.configure("web_playtest", factory, false)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	var projector: TelemetryProjector = factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", false, "web_flow_test")
	_collection.bind(run)
	assert_true(await _wait(func() -> bool: return not support.pending()))
	var source_path: String = "run_records/" + run.state.run_id + ".jsonl"
	var original: String = backend.files()[source_path]
	var state: Dictionary = RunSnapshot.capture(run)
	persistence.fail_prefix = "run_records/"
	persistence.fail_write = true
	_collection.close("test_completed")
	assert_true(projector.ended)
	assert_true(await _wait(func() -> bool: return not backend.error.is_empty()))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(backend.files()[source_path], original)
	var reader: TelemetryReader = TelemetryReader.new()
	var events: Array[Dictionary] = reader.read_text(backend.files()["telemetry/" + run.state.run_id + ".jsonl"])
	assert_false(reader.complete)
	for event: Dictionary in events: assert_ne(event.event_name, "run_ended")
	assert_eq(RunSnapshot.capture(run), state)
	assert_ne(support.error(), "")

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())
