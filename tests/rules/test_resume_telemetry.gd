extends GutTest

class MemorySink extends TelemetrySink:
	var events: Array[Dictionary] = []
	func append_event(event: Dictionary) -> TelemetryWriteResult:
		events.append(event.duplicate(true))
		return TelemetryWriteResult.new()

class FailedSaveFiles extends CheckpointFiles:
	func write_text(path: String, text: String) -> Error:
		return ERR_CANT_CREATE if path.get_file() == "checkpoint.tmp" else super.write_text(path, text)

var _directories: Array[String] = []
var _collections: Array[RunCollection] = []

func after_each() -> void:
	for collection: RunCollection in _collections:
		collection.suspend_for_checkpoint()
		collection.free()
	_collections.clear()
	for directory: String in _directories:
		_remove(directory)
	_directories.clear()

func _remove(directory: String) -> void:
	assert_true(directory.begins_with("user://resume-telemetry-tests/"))
	for name: String in DirAccess.get_directories_at(directory): _remove(directory.path_join(name))
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "human", false)
	return run

func _directory() -> String:
	var directory: String = "user://resume-telemetry-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.append(directory)
	return directory

func _resume(run: RunController) -> Dictionary:
	return {"schema": "telemetry-resume-v1", "run_id": run.state.run_id, "checkpoint_id": "checkpoint-test", "parent_segment_id": "parent-session", "parent_telemetry_seq": "8", "parent_persisted_seq": "5", "parent_last_event_id": run.state.run_id + ":8", "parent_last_event_hash": "a".repeat(64), "record_seq": str(run.recorder.records.size()), "next_rule_event_id": str(run.state.ledger.next_event_id()), "anchor_state_hash": RunSnapshot.digest(RunSnapshot.capture(run)), "lineage_known": true}

func test_resume_header_has_unique_segment_event_identity_and_never_replays_run_started() -> void:
	var run: RunController = _run()
	var header: Dictionary = run.recorder.records[0].duplicate(true)
	header.metadata["resume"] = _resume(run)
	var first: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "resume-session-a")
	var second: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "resume-session-b")
	first.observe_record(header)
	second.observe_record(header)
	assert_eq(first.events.size(), 1)
	assert_eq(first.events[0].event_name, "run_resumed")
	assert_eq(first.events[0].schema_version, "3")
	assert_eq(first.events[0].event_id, run.state.run_id + ":resume-session-a:1")
	assert_ne(first.events[0].event_id, second.events[0].event_id)
	assert_eq(first.events[0].run_id, second.events[0].run_id)
	assert_eq(TelemetrySchema.validate(first.events[0]), "")
	first.play_started()
	second.play_started()
	assert_eq(first.events.back().run_id, run.state.run_id)

func test_checkpoint_wrapper_preserves_accepted_and_persisted_anchor_without_changing_rules() -> void:
	var run: RunController = _run()
	var state: Dictionary = RunSnapshot.capture(run)
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	var trace: Dictionary = {"schema": "checkpoint-telemetry-v1", "run_id": run.state.run_id, "segment_id": "parent-session", "accepted_seq": "8", "persisted_seq": "5", "last_event_id": run.state.run_id + ":8", "record_seq": str(run.recorder.records.size()), "next_rule_event_id": str(run.state.ledger.next_event_id())}
	encoded["telemetry"] = trace
	var directory: String = _directory()
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), policy)
	assert_true(session.save_encoded(encoded).ok)
	var restored: Dictionary = session.load_candidate()
	assert_true(restored.ok)
	assert_true(restored.has("resume_context"))
	if restored.has("resume_context"):
		assert_eq(restored.resume_context.trace, trace)
		assert_eq(restored.resume_context.record_seq, str(run.recorder.records.size()))
		assert_eq(restored.resume_context.state_hash, RunSnapshot.digest(state))
	assert_eq(RunSnapshot.capture(run), state)
	assert_eq(RunSnapshot.capture(restored.run), state)

func _tracking(directory: String) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	var collection: RunCollection = RunCollection.new()
	_collections.append(collection)
	var factory: TelemetryFactory = TelemetryFactory.new("original-session")
	factory.directory = directory
	factory.record_directory = directory.path_join("records")
	collection.configure("automated_integration", factory)
	var projector: TelemetryProjector = factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", true, "resume_test", factory.record_directory)
	collection.bind(run)
	collection.flush()
	return {"run": run, "collection": collection, "projector": projector, "factory": factory}

func _settle(run: RunController) -> void:
	for index: int in range(40):
		if RunCheckpointCodec.safety_error(run).is_empty(): return
		run.advance()

func test_real_resume_files_preserve_originals_and_new_commands_match_without_history_emission() -> void:
	var directory: String = _directory()
	var original: Dictionary = _tracking(directory)
	var run: RunController = original.run
	var trace: Dictionary = original.collection.checkpoint_trace(run)
	assert_eq(trace.accepted_seq, trace.persisted_seq)
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = trace
	var slot: String = directory.path_join("slot")
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(slot), RunCheckpointCodec.manifest(run))
	assert_true(session.save_encoded(encoded).ok)
	assert_true(run.execute_command(GreedyBot.new(23).choose(run)).accepted)
	_settle(run)
	original.collection.suspend_for_checkpoint()
	var old_log: String = (original.projector.sink as LocalJsonlSink).path
	var old_hash: String = FileAccess.get_sha256(old_log)
	var restored: Dictionary = session.load_candidate()
	assert_true(restored.ok)
	var projector: TelemetryProjector = original.collection.resume("automated_integration", restored.run, restored.resume_context, true)
	assert_eq(projector.events.size(), 1, "only resume boundary is published, not the saved rule prefix")
	assert_eq(projector.events[0].event_name, "run_resumed")
	assert_eq(projector.events[0].resume.parent_segment_id, "original-session")
	assert_ne(projector.events[0].session_id, "original-session")
	assert_eq(projector.events[0].run_id, run.state.run_id)
	var control: RunController = session.load_candidate().run
	var command: RunCommand = GreedyBot.new(23).choose(restored.run)
	assert_true(restored.run.execute_command(command).accepted)
	assert_true(control.execute_command(CommandCodec.decode(CommandCodec.encode(command))).accepted)
	_settle(restored.run)
	_settle(control)
	assert_eq(RunSnapshot.capture(restored.run), RunSnapshot.capture(control))
	original.collection.suspend_for_checkpoint()
	assert_eq(FileAccess.get_sha256(old_log), old_hash)
	var reader: TelemetryReader = TelemetryReader.new()
	var rows: Array[Dictionary] = reader.read_file((projector.sink as LocalJsonlSink).path)
	assert_eq(reader.error, "")
	assert_true(reader.segment_complete)
	assert_false(reader.complete, "segment close is not a logical natural ending")
	assert_gt(rows.size(), 1)
	assert_eq(rows.back().event_name, "resume_segment_closed")
	var records: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(restored.run.recorder.path).split("\n", false): records.append(JSON.parse_string(line))
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(records), replay.error)
	assert_eq(RunSnapshot.capture(replay.run), RunSnapshot.capture(restored.run))

func test_missing_wrapper_schema_with_replacement_key_is_rejected_and_bad_trace_does_not_block_save() -> void:
	var run: RunController = _run()
	var directory: String = _directory()
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), RunCheckpointCodec.manifest(run))
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = RefCounted.new()
	assert_true(session.save_encoded(encoded).ok, "telemetry shape failure must not prevent verified rule saving")
	assert_eq(session.load_candidate().resume_context.trace.status, "invalid_trace")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("primary.json")))
	record.payload.erase("schema")
	record.payload["replacement"] = "junk"
	record.erase("digest")
	record.digest = JSON.stringify(record, "", true).sha256_text()
	var file: FileAccess = FileAccess.open(directory.path_join("primary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "", true))
	file.close()
	assert_eq(session.load_candidate().reason, "invalid_package")

func _family() -> Dictionary:
	var run: RunController = _run()
	var parent: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "parent-session")
	parent.observe_record(run.recorder.records[0])
	var trace: Dictionary = parent.checkpoint_trace(run.recorder.records.size(), run.state.ledger.next_event_id())
	var context: Dictionary = {"checkpoint_id": "checkpoint-test", "trace": trace}
	var header: Dictionary = TelemetryResume.header(run, context, "unknown", "unknown")
	parent.play_started() # A real observed tail newer than the checkpoint must be retained separately.
	var child: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "child-session")
	child.begin_resume(header, run.recorder.records)
	child.play_started()
	var raw: Array[Dictionary] = parent.events.duplicate(true)
	raw.append_array(child.events.duplicate(true))
	return {"run": run, "parent": parent, "child": child, "header": header, "raw": raw}

func test_lineage_reassembles_unique_chain_once_and_preserves_discarded_tail_and_source_events() -> void:
	var family: Dictionary = _family()
	var normalized: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(family.raw)
	assert_eq(normalized.errors, [])
	assert_eq(normalized.streams.size(), 1)
	assert_eq(normalized.streams[0].size(), 3)
	assert_eq(normalized.branches[0].discarded_event_ids, [family.parent.events[1].event_id])
	var starts: int = 0
	for row: Dictionary in normalized.streams[0]:
		if row.event_name == "run_started": starts += 1
		assert_eq(TelemetrySchema.validate(row), "")
		assert_eq(row.source_event_id, row.source_event.event_id)
	assert_eq(starts, 1)
	assert_eq(family.raw.size(), 4)
	var report: TelemetryReport = TelemetryReport.new()
	report.add(family.parent.events)
	report.add(family.child.events)
	report.add(family.child.events)
	assert_eq(report.summary().runs, 1)
	assert_eq(report.summary().events, 3)
	assert_eq(report.errors, [])
	var directory: String = _directory()
	assert_true(report.write(directory))
	var lineage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("resume_lineage.json")))
	assert_eq(lineage.raw_events.size(), 6, "repeated input is retained as source evidence, not another sample")

func test_ambiguous_resume_leaves_and_missing_or_bad_anchors_do_not_create_natural_samples() -> void:
	var family: Dictionary = _family()
	var sibling: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "sibling-session")
	sibling.begin_resume(family.header, family.run.recorder.records)
	var raw: Array[Dictionary] = family.raw.duplicate(true)
	raw.append_array(sibling.events)
	var ambiguous: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(raw)
	assert_eq(ambiguous.errors[0].reason, "ambiguous_resume_branches")
	assert_eq(ambiguous.streams, [])
	var missing: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(family.child.events)
	assert_eq(missing.errors[0].reason, "missing_resume_parent")
	var altered: Array[Dictionary] = family.raw.duplicate(true)
	for row: Dictionary in altered:
		if row.schema_version == "3":
			row.resume.parent_last_event_hash = "b".repeat(64)
			if row.event_name == "run_resumed": row.payload.resume = row.resume.duplicate(true)
	var bad_anchor: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(altered)
	assert_eq(bad_anchor.errors[0].reason, "resume_anchor_mismatch")
	var changed_config: Array[Dictionary] = family.raw.duplicate(true)
	for row: Dictionary in changed_config:
		if row.schema_version == "3": row.collection_config_hash = "different-observation-policy"
	assert_eq(preload("res://services/telemetry/telemetry_lineage.gd").normalize(changed_config).errors[0].reason, "resume_metadata_mismatch:collection_config_hash")

func test_failed_save_keeps_old_anchor_while_later_observations_are_real_and_preserved() -> void:
	var directory: String = _directory()
	var tracked: Dictionary = _tracking(directory)
	var run: RunController = tracked.run
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var slot: String = directory.path_join("slot")
	var old: Dictionary = RunCheckpointCodec.encode(run)
	old["telemetry"] = tracked.collection.checkpoint_trace(run)
	assert_true(RunCheckpointSession.new(CheckpointStore.new(slot), policy).save_encoded(old).ok)
	assert_true(run.execute_command(GreedyBot.new(23).choose(run)).accepted)
	_settle(run)
	tracked.collection.flush()
	var newer: Dictionary = RunCheckpointCodec.encode(run)
	newer["telemetry"] = tracked.collection.checkpoint_trace(run)
	assert_gt(newer.telemetry.accepted_seq.to_int(), old.telemetry.accepted_seq.to_int())
	assert_false(RunCheckpointSession.new(CheckpointStore.new(slot, FailedSaveFiles.new()), policy).save_encoded(newer).ok)
	var restored: Dictionary = RunCheckpointSession.new(CheckpointStore.new(slot), policy).load_candidate()
	assert_true(restored.ok)
	assert_eq(restored.resume_context.trace, old.telemetry)
	assert_ne(restored.resume_context.trace, newer.telemetry)
	assert_eq(RunSnapshot.capture(restored.run), old.payload.state)

func test_worker_prepares_rule_file_once_and_telemetry_io_failure_does_not_block_rules() -> void:
	var directory: String = _directory()
	var tracked: Dictionary = _tracking(directory)
	var run: RunController = tracked.run
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var slot: String = directory.path_join("slot")
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = tracked.collection.checkpoint_trace(run)
	assert_true(RunCheckpointSession.new(CheckpointStore.new(slot), policy).save_encoded(encoded).ok)
	var plan: Dictionary = tracked.collection.plan_resume(true)
	var worker: CheckpointJob = CheckpointJob.new()
	assert_eq(worker.start_load(CheckpointStore.new(slot), policy, 10000000, plan), OK)
	while not worker.is_done(): await get_tree().process_frame
	var candidate: Dictionary = worker.finish()
	assert_true(candidate.ok)
	assert_true(FileAccess.file_exists(candidate.run.recorder.path), "prefix exists before scene takeover")
	var before: String = FileAccess.get_sha256(candidate.run.recorder.path)
	var projector: TelemetryProjector = tracked.collection.resume("automated_integration", candidate.run, candidate.resume_context, true)
	assert_eq(FileAccess.get_sha256(candidate.run.recorder.path), before, "adoption must not serialize or emit the prefix a second time")
	assert_eq(projector.events.size(), 1)
	assert_eq(projector.events[0].segment_id, plan.session_id)
	tracked.collection.suspend_for_checkpoint()
	var blocker: String = directory.path_join("blocked-directory")
	var file: FileAccess = FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("not-a-directory")
	file.close()
	var broken_plan: Dictionary = plan.duplicate(true)
	broken_plan.session_id = "failed-preparation-session"
	broken_plan.record_directory = blocker
	var second: CheckpointJob = CheckpointJob.new()
	assert_eq(second.start_load(CheckpointStore.new(slot), policy, 10000000, broken_plan), OK)
	while not second.is_done(): await get_tree().process_frame
	var loaded: Dictionary = second.finish()
	assert_true(loaded.ok, "rule restore survives observation evidence path failure")
	assert_false(loaded.run.recorder.error.is_empty())
	assert_eq(RunSnapshot.capture(loaded.run), encoded.payload.state)
	assert_true(RunCheckpointSession.new(CheckpointStore.new(slot), policy).save(loaded.run).ok)
	var failed_projector: TelemetryProjector = TelemetryProjector.new(LocalJsonlSink.new("failed-sink", blocker), "failed-sink-session")
	failed_projector.observe_record(loaded.run.recorder.records[0])
	var observed: Dictionary = RunCheckpointCodec.encode(loaded.run)
	observed["telemetry"] = failed_projector.checkpoint_trace(loaded.run.recorder.records.size(), loaded.run.state.ledger.next_event_id())
	assert_eq(observed.telemetry.status, "telemetry_failed")
	assert_true(RunCheckpointSession.new(CheckpointStore.new(slot), policy).save_encoded(observed).ok)
	assert_eq(RunCheckpointSession.new(CheckpointStore.new(slot), policy).load_candidate().resume_context.trace.status, "telemetry_failed")
	tracked.collection.resume("automated_integration", loaded.run, loaded.resume_context, false)
	tracked.collection.suspend_for_checkpoint()
	var healthy: Dictionary = RunCheckpointSession.new(CheckpointStore.new(slot), policy).load_candidate()
	tracked.collection.resume("automated_integration", healthy.run, healthy.resume_context, false)
	assert_string_contains(tracked.collection.save_status(), "部分记录不完整")

func test_frozen_root_observation_resumes_without_duplicate_action_or_skill_events() -> void:
	var directory: String = _directory()
	var tracked: Dictionary = _tracking(directory)
	var run: RunController = tracked.run
	var bot: GreedyBot = GreedyBot.new(100023)
	for index: int in range(500):
		if run.state.rewards.active_offer != null or run.state.is_game_over: break
		if run.state.phase == RunState.Phase.INPUT: run.execute_command(bot.choose(run))
		else: run.advance()
	assert_not_null(run.state.rewards.active_offer)
	if run.state.rewards.active_offer == null: return
	tracked.collection.flush()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = tracked.collection.checkpoint_trace(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory.path_join("slot")), encoded.manifest)
	assert_true(session.save_encoded(encoded).ok)
	var loaded: Dictionary = session.load_candidate()
	assert_true(loaded.ok)
	var context: Dictionary = loaded.resume_context
	var projector: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "frozen-resume")
	projector.begin_resume(TelemetryResume.header(loaded.run, context, "automated_integration", "unknown"), loaded.run.recorder.records)
	loaded.run.recorder.record_appended.connect(projector.observe_record)
	assert_eq(projector.events.size(), 1)
	assert_eq(projector.observation().root_complete, tracked.projector.observation().root_complete)
	var baseline: int = tracked.projector.events.size()
	for index: int in range(100):
		if run.state.phase == RunState.Phase.INPUT: break
		if run.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(run)
			assert_true(run.execute_command(command).accepted)
			assert_true(loaded.run.execute_command(CommandCodec.decode(CommandCodec.encode(command))).accepted)
		else:
			run.advance()
			loaded.run.advance()
		assert_eq(RunSnapshot.capture(loaded.run), RunSnapshot.capture(run))
	var source_count: Dictionary[String, int] = {}
	for event: Dictionary in tracked.projector.events.slice(baseline):
		if event.event_name in ["action_resolved", "skill_acquired"]: source_count[event.event_name] = source_count.get(event.event_name, 0) + 1
	var resumed_count: Dictionary[String, int] = {}
	for event: Dictionary in projector.events:
		if event.event_name in ["action_resolved", "skill_acquired"]: resumed_count[event.event_name] = resumed_count.get(event.event_name, 0) + 1
	assert_eq(resumed_count, source_count)
	assert_eq(projector.error, "")

func test_accepted_but_unpersisted_anchor_is_not_promoted_and_missing_tail_is_diagnostic() -> void:
	var directory: String = _directory()
	var tracked: Dictionary = _tracking(directory)
	var run: RunController = tracked.run
	tracked.projector.play_started()
	var trace: Dictionary = tracked.collection.checkpoint_trace(run)
	assert_gt(trace.accepted_seq.to_int(), trace.persisted_seq.to_int())
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	encoded["telemetry"] = trace
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory.path_join("slot")), encoded.manifest)
	assert_true(session.save_encoded(encoded).ok)
	var restored: Dictionary = session.load_candidate()
	assert_eq(restored.resume_context.trace.persisted_seq, trace.persisted_seq)
	assert_eq(restored.resume_context.trace.accepted_seq, trace.accepted_seq)
	var reader: TelemetryReader = TelemetryReader.new()
	var persisted: Array[Dictionary] = reader.read_file((tracked.projector.sink as LocalJsonlSink).path)
	assert_eq(str(persisted.size()), trace.persisted_seq)
	var child: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "unpersisted-resume")
	child.begin_resume(TelemetryResume.header(restored.run, restored.resume_context, "automated_integration", tracked.factory.commit_id), restored.run.recorder.records)
	var raw: Array[Dictionary] = persisted.duplicate(true)
	raw.append_array(child.events)
	var unavailable: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(raw)
	assert_eq(unavailable.errors[0].reason, "resume_anchor_not_persisted")
	assert_eq(unavailable.streams, [])
	tracked.collection.flush()
	raw = reader.read_file((tracked.projector.sink as LocalJsonlSink).path)
	raw.append_array(child.events)
	assert_eq(preload("res://services/telemetry/telemetry_lineage.gd").normalize(raw).errors, [])

func test_rule_bad_primary_fallback_uses_previous_telemetry_anchor_and_keeps_parent_tail() -> void:
	var directory: String = _directory()
	var tracked: Dictionary = _tracking(directory)
	var run: RunController = tracked.run
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var slot: String = directory.path_join("slot")
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(slot), policy)
	var older: Dictionary = RunCheckpointCodec.encode(run)
	older["telemetry"] = tracked.collection.checkpoint_trace(run)
	assert_true(session.save_encoded(older).ok)
	assert_true(run.execute_command(GreedyBot.new(23).choose(run)).accepted)
	_settle(run)
	tracked.collection.flush()
	var newer: Dictionary = RunCheckpointCodec.encode(run)
	newer["telemetry"] = tracked.collection.checkpoint_trace(run)
	assert_true(session.save_encoded(newer).ok)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot.path_join("primary.json")))
	var payload: Dictionary = JSON.parse_string(record.payload.payload_json)
	payload.state_hash = "broken"
	record.payload.payload_json = JSON.stringify(payload, "", true, true)
	record.erase("digest")
	record.digest = JSON.stringify(record, "", true).sha256_text()
	var file: FileAccess = FileAccess.open(slot.path_join("primary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "", true))
	file.close()
	var restored: Dictionary = session.load_candidate()
	assert_true(restored.ok)
	assert_true(restored.fallback)
	assert_eq(restored.resume_context.trace, older.telemetry)
	assert_ne(restored.resume_context.trace, newer.telemetry)
	var parent_rows: Array[Dictionary] = tracked.projector.events.duplicate(true)
	var child: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "fallback-resume")
	child.begin_resume(TelemetryResume.header(restored.run, restored.resume_context, "automated_integration", tracked.factory.commit_id), restored.run.recorder.records)
	parent_rows.append_array(child.events)
	var normalized: Dictionary = preload("res://services/telemetry/telemetry_lineage.gd").normalize(parent_rows)
	assert_eq(normalized.errors, [])
	assert_eq(normalized.streams.size(), 1)
	assert_gt(normalized.branches[0].discarded_event_ids.size(), 0)
