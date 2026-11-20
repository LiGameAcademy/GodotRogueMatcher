extends GutTest

const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
const PERSISTENCE: Script = preload("res://tests/support/web_telemetry_persistence.gd")
const SINK: Script = preload("res://services/telemetry/web_telemetry_sink.gd")
const NAME: String = "telemetry/run-1--session-1.jsonl"

func test_projector_trace_uses_actual_acknowledgement_without_mutating_rules() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	var backend: BACKEND = BACKEND.new(persistence)
	assert_true((await backend.open()).ok)
	persistence.hold = true
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	var factory: TelemetryFactory = TelemetryFactory.new("s-web-backend")
	factory.sink_factory = func(storage_id: String) -> TelemetrySink: return SINK.new(storage_id, backend)
	var projector: TelemetryProjector = factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "human", false, "web_test")
	var original: Dictionary = RunSnapshot.capture(run)
	var trace: Dictionary = projector.checkpoint_trace(run.recorder.records.size(), run.state.ledger.next_event_id())
	assert_eq(trace.accepted_seq, "1")
	assert_eq(trace.persisted_seq, "0")
	assert_eq(trace.last_event_hash, RunSnapshot.digest(projector.events.back()))
	assert_true(await _wait(func() -> bool: return persistence.writing))
	persistence.hold = false
	persistence.release_write.emit()
	assert_true(await _wait(func() -> bool: return not backend.pending()))
	trace = projector.checkpoint_trace(run.recorder.records.size(), run.state.ledger.next_event_id())
	assert_eq(trace.persisted_seq, "1")
	persistence.fail_write = true
	projector.play_started()
	assert_true(await _wait(func() -> bool: return not backend.error.is_empty()))
	assert_eq(projector.checkpoint_trace(run.recorder.records.size(), run.state.ledger.next_event_id()).status, "telemetry_failed")
	assert_eq(RunSnapshot.capture(run), original)
	assert_false(projector.sink.close().succeeded())

func test_acknowledgement_waits_for_transaction_and_serializes_later_appends() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	var backend: BACKEND = BACKEND.new(persistence)
	assert_true((await backend.open()).ok)
	assert_true(backend.reserve(NAME))
	persistence.hold = true
	var acknowledgements: Array[int] = []
	backend.acknowledged.connect(func(_name: String, sequence: int) -> void: acknowledgements.append(sequence))
	assert_true(backend.append(NAME, "{\"seq\":1}\n", 1))
	assert_false(backend.append(NAME, "{\"duplicate\":true}\n", 1), "queued watermark cannot repeat")
	assert_true(await _wait(func() -> bool: return persistence.writing))
	assert_false(backend.append(NAME, "{\"duplicate\":true}\n", 1), "inflight watermark cannot repeat")
	assert_true(backend.files().is_empty())
	assert_true(acknowledgements.is_empty())
	assert_true(backend.append(NAME, "{\"seq\":2}\n", 2))
	assert_false(backend.append(NAME, "{\"older\":true}\n", 1), "queued watermark cannot decrease")
	persistence.hold = false
	persistence.release_write.emit()
	assert_true(await _wait(func() -> bool: return not backend.pending()))
	assert_eq(acknowledgements, [1, 2])
	assert_eq(backend.files()[NAME], "{\"seq\":1}\n{\"seq\":2}\n")
	assert_eq(persistence.stored[NAME].revision, 2)
	assert_false(backend.append(NAME, "{\"duplicate\":true}\n", 2), "acknowledged watermark cannot repeat")

func test_failed_append_preserves_acknowledged_prefix_and_stops_new_writes() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	var backend: BACKEND = BACKEND.new(persistence)
	assert_true((await backend.open()).ok)
	assert_true(backend.reserve(NAME))
	assert_true(backend.append(NAME, "{\"seq\":1}\n", 1))
	assert_true(await _wait(func() -> bool: return not backend.pending()))
	var original: Dictionary = persistence.stored.duplicate(true)
	persistence.fail_write = true
	assert_true(backend.append(NAME, "{\"seq\":2}\n", 2))
	assert_true(await _wait(func() -> bool: return not backend.error.is_empty()))
	assert_eq(persistence.stored, original)
	assert_eq(backend.files()[NAME], "{\"seq\":1}\n")
	assert_false(backend.append(NAME, "{\"seq\":3}\n", 3))

func test_reopened_files_cannot_be_reserved_as_a_new_segment() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	persistence.stored[NAME] = {"schema": "web-collection-file-v1", "revision": 1, "text": "{}\n"}
	var backend: BACKEND = BACKEND.new(persistence)
	assert_true((await backend.open()).ok)
	assert_false(backend.reserve(NAME))
	assert_false(backend.append(NAME, "{}\n", 1))
	assert_false(backend.reserve("telemetry/../old.jsonl"))
	assert_true(backend.reserve("sessions/new-session.jsonl"))

func test_unknown_snapshot_is_rejected_without_modifying_original() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	persistence.stored[NAME] = {"schema": "unknown", "revision": 1, "text": "{}\n"}
	var original: Dictionary = persistence.stored.duplicate(true)
	var backend: BACKEND = BACKEND.new(persistence)
	assert_false((await backend.open()).ok)
	assert_false(backend.ready)
	assert_false(backend.reserve(NAME))
	assert_eq(persistence.stored, original)

func test_export_snapshot_includes_other_writers_without_replacing_local_revisions() -> void:
	var persistence: PERSISTENCE = PERSISTENCE.new()
	var peer_persistence: PERSISTENCE = PERSISTENCE.new()
	peer_persistence.stored = persistence.stored
	var backend: BACKEND = BACKEND.new(persistence)
	var peer: BACKEND = BACKEND.new(peer_persistence)
	assert_true((await backend.open()).ok)
	assert_true((await peer.open()).ok)
	assert_true(backend.reserve(NAME))
	assert_true(backend.append(NAME, "{\"seq\":1}\n", 1))
	assert_true(await _wait(func() -> bool: return not backend.pending()))
	var other: String = "telemetry/other--session.jsonl"
	assert_true(peer.reserve(other))
	assert_true(peer.append(other, "{}\n", 1))
	assert_true(await _wait(func() -> bool: return not peer.pending()))
	assert_false(backend.files().has(other))
	var snapshot: Dictionary = await backend.snapshot()
	assert_true(snapshot.ok, snapshot.reason)
	assert_eq(snapshot.files[other], "{}\n")
	assert_false(backend.files().has(other), "readonly export cannot replace writer cache")
	assert_true(backend.append(NAME, "{\"seq\":2}\n", 2))
	assert_true(await _wait(func() -> bool: return not backend.pending()))
	assert_eq(persistence.stored[NAME].revision, 2)

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())
