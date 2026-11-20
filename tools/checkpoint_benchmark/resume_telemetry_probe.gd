extends SceneTree

## Produces real source files and a repeat-importable analysis report in an isolated APPDATA.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stamp: String = "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var directory: String = "user://resume-telemetry-probe/" + stamp
	var factory: TelemetryFactory = TelemetryFactory.new("probe-parent-" + stamp)
	factory.directory = directory.path_join("telemetry")
	factory.record_directory = directory.path_join("records")
	var collection: RunCollection = RunCollection.new()
	collection.configure("automated_integration", factory)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	var parent: TelemetryProjector = factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", true, "resume_probe", factory.record_directory)
	collection.bind(run)
	collection.flush()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = collection.checkpoint_trace(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory.path_join("slot")), encoded.manifest)
	var saved: Dictionary = session.save_encoded(encoded)
	if not saved.ok: return _fail("save:" + saved.reason, collection)
	var plan: Dictionary = collection.plan_resume(true)
	if not run.execute_command(GreedyBot.new(23).choose(run)).accepted: return _fail("parent_command", collection)
	_settle(run)
	var expected: Dictionary = RunSnapshot.capture(run)
	collection.suspend_for_checkpoint()
	var parent_path: String = (parent.sink as LocalJsonlSink).path
	var parent_hash: String = FileAccess.get_sha256(parent_path)
	var worker: CheckpointJob = CheckpointJob.new()
	if worker.start_load(CheckpointStore.new(directory.path_join("slot")), encoded.manifest, 10000000, plan) != OK:
		return _fail("load_start", collection)
	while not worker.is_done(): await process_frame
	var loaded: Dictionary = worker.finish()
	if not loaded.ok: return _fail("load:" + loaded.reason, collection)
	var child: TelemetryProjector = collection.resume("automated_integration", loaded.run, loaded.resume_context, true)
	var only_resume: bool = child.events.size() == 1 and child.events[0].event_name == "run_resumed"
	if not loaded.run.execute_command(GreedyBot.new(23).choose(loaded.run)).accepted: return _fail("child_command", collection)
	_settle(loaded.run)
	var state_equal: bool = RunSnapshot.capture(loaded.run) == expected
	collection.suspend_for_checkpoint()
	var child_path: String = (child.sink as LocalJsonlSink).path
	var report: TelemetryReport = TelemetryReport.new()
	var reader: TelemetryReader = TelemetryReader.new()
	report.add(reader.read_file(parent_path), reader.error)
	report.add(reader.read_file(child_path), reader.error)
	report.add(reader.read_file(child_path), reader.error)
	var output: String = "res://.godot/resume-probe-report-" + stamp
	if not report.write(output): return _fail("report:" + report.error, collection)
	var summary: Dictionary = report.summary()
	var action_count: int = 0
	for event: Dictionary in report.events:
		if event.event_name == "action_resolved": action_count += 1
	var result: Dictionary = {
		"kind": "real_resume_telemetry_probe", "pid": OS.get_process_id(), "engine": Engine.get_version_info(),
		"source_directory": ProjectSettings.globalize_path(factory.directory), "report_directory": ProjectSettings.globalize_path(output),
		"run_id": run.state.run_id, "parent_session": factory.session_id, "child_session": collection.factory.session_id,
		"parent_file_unchanged": FileAccess.get_sha256(parent_path) == parent_hash, "only_resume_emitted_on_attach": only_resume,
		"same_next_command_snapshot": state_equal, "runs": summary.runs, "analysis_action_count": action_count,
		"raw_parent_actions": _actions(parent.events), "raw_child_actions": _actions(child.events), "errors": summary.errors,
		"branches": summary.resume_branches, "trace": encoded.telemetry,
	}
	result["ok"] = only_resume and state_equal and result.parent_file_unchanged and summary.runs == 1 and action_count == 1 and result.raw_parent_actions == 1 and result.raw_child_actions == 1 and summary.errors.is_empty()
	var file: FileAccess = FileAccess.open("res://.godot/resume-probe-last.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t", true, true))
	file.close()
	print("RESUME_TELEMETRY_PROBE " + JSON.stringify(result))
	collection.free()
	quit(0 if result.ok else 1)

func _actions(events: Array[Dictionary]) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event.event_name == "action_resolved": count += 1
	return count

func _settle(run: RunController) -> void:
	for index: int in range(40):
		if RunCheckpointCodec.safety_error(run).is_empty(): return
		run.advance()

func _fail(reason: String, collection: RunCollection) -> void:
	push_error(reason)
	collection.suspend_for_checkpoint()
	collection.free()
	quit(1)
