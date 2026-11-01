extends GutTest

## Real native telemetry ACK and snapshot-linked command segments; unknown ancestry stays unknown.
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const RESTORE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const SEGMENT: Script = preload("res://services/run_checkpoint/snapshot_segment.gd")
class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
var _directory: String = ""

func after_each() -> void:
	if _directory.is_empty() or not DirAccess.dir_exists_absolute(_directory): return
	for file: String in DirAccess.get_files_at(_directory): DirAccess.remove_absolute(_directory.path_join(file))
	DirAccess.remove_absolute(_directory)
	_directory = ""

func test_real_persisted_parent_anchor_and_new_segment_lineage_without_rule_prefix() -> void:
	_directory = "user://snapshot-segment-tests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	var factory: TelemetryFactory = TelemetryFactory.new("snapshot-parent")
	factory.directory = _directory
	var projector: TelemetryProjector = factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", false, Engine.get_version_info().hash)
	projector.snapshot_anchor(RunSnapshot.digest(RESTORE.project(run)))
	assert_true(SEGMENT.trace(run, projector).is_empty(), "unflushed accepted row is not durable")
	projector.flush_pending()
	var trace: Dictionary = SEGMENT.trace(run, projector)
	assert_false(trace.is_empty(), projector.error)
	if trace.is_empty(): return
	var parent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string((projector.sink as LocalJsonlSink).path).strip_edges().split("\n")[-1])
	assert_eq(parent.event_id, trace.last_event_id)
	var store: CheckpointStore = CheckpointStore.new(_directory)
	var saved: Dictionary = await SNAPSHOT.save(store, run, trace)
	assert_true(saved.ok, saved.reason)
	var loaded: Dictionary = SNAPSHOT.load(CheckpointStore.new(_directory), SNAPSHOT.manifest(run))
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	assert_eq(loaded.trace, trace)
	var next_factory: TelemetryFactory = TelemetryFactory.new("snapshot-child")
	next_factory.directory = _directory
	var started: Dictionary = SEGMENT.begin(loaded.run, next_factory.session_id, {"trace": loaded.trace, "parent_event": parent}, next_factory)
	assert_true(started.ok, started.reason)
	if not started.ok: return
	assert_true(started.lineage_known)
	assert_eq(started.projector.events[0].event_name, "run_resumed")
	assert_eq(TelemetrySchema.validate(started.projector.events[0]), "")
	var lines: Array[Dictionary] = projector.events.duplicate(true)
	lines.append_array(started.projector.events)
	var lineage: Dictionary = TelemetryLineage.normalize(lines)
	assert_eq(lineage.errors, [])
	loaded.run.recorder.open_resume_file(_directory, "commands-" + next_factory.session_id, started.projector.events[0].resume)
	loaded.run.recorder.close_interrupted()
	var recorded: Array[Dictionary] = RuleReplay.new().read_file(loaded.run.recorder.path)
	assert_eq(recorded.size(), 2, "only snapshot header/checkpoint; no old record prefix")
	if recorded.is_empty(): return
	assert_eq(recorded[0].kind, "SnapshotHeader")
	assert_true(SEGMENT.replay(recorded, SNAPSHOT.manifest(run)).ok)
	started.projector.sink.close()
	projector.sink.close()

func test_missing_or_mismatched_parent_never_claims_known_or_blocks_valid_snapshot() -> void:
	var source: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	source.initialize()
	var frozen: Dictionary = SNAPSHOT.freeze(source)
	var restored: Dictionary = SNAPSHOT.decode(frozen.payload, SNAPSHOT.manifest(source))
	assert_true(restored.ok)
	if not restored.ok: return
	var factory: TelemetryFactory = TelemetryFactory.new("snapshot-unknown")
	# Memory sink has no durable watermark and must never become a known ancestor.
	factory.sink_factory = func(_id: String) -> TelemetrySink: return MemorySink.new()
	var started: Dictionary = SEGMENT.begin(restored.run, factory.session_id, {"trace": {"persisted_seq": "100"}, "parent_event": {}}, factory)
	assert_true(started.ok, started.reason)
	assert_false(started.lineage_known)
	assert_eq(started.projector.events[0].resume.parent_segment_id, "")
	assert_eq(TelemetrySchema.validate(started.projector.events[0]), "")
	assert_eq(RESTORE.project(source), RESTORE.project(restored.run))