extends GutTest

func test_local_sink_accepts_in_memory_then_persists_one_batch() -> void:
	var sink: LocalJsonlSink = LocalJsonlSink.new("batch-" + str(Time.get_ticks_usec()), "user://collection_tests")
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 17)
	run.initialize()
	var recorder: RunRecorder = RunRecorder.new()
	var telemetry: TelemetryProjector = TelemetryProjector.new(sink, "batch-session")
	recorder.record_appended.connect(telemetry.observe_record)
	recorder.begin(run, "human", false)
	assert_gt(sink.accepted_seq, sink.persisted_seq)
	assert_eq(sink.flush_count, 0)
	telemetry.flush_pending()
	assert_eq(sink.accepted_seq, sink.persisted_seq)
	assert_eq(sink.flush_count, 1)
	assert_gt(FileAccess.get_file_as_string(sink.path).length(), 0)
	recorder.finish(run, "abandoned", "window_close_requested")
	assert_eq(sink.accepted_seq, sink.persisted_seq)
	assert_true(TelemetryReader.new().read_file(sink.path).size() > 1)

func test_pressure_snapshot_computes_real_empty_components_without_rng() -> void:
	var state: Dictionary = {"pieces": [{"coordinate": ["1", "0"]}, {"coordinate": ["1", "1"]}]}
	var pressure: Dictionary = TelemetryFacts.pressure(state, 3, 2)
	assert_eq(pressure.n, 2)
	assert_eq(pressure.empty, 4)
	assert_eq(pressure.L, 2)
	assert_almost_eq(pressure.P, 100.0 * (0.7 * 2.0 / 6.0 + 0.3 * 0.5), 0.001)
