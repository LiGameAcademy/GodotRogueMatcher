extends GutTest

## Real normal-play prefix that exposed binary64 loss through the JSON parser.
const TRANSPORT: Script = preload("res://services/run_checkpoint/checkpoint_float_transport.gd")
var _directory: String

func after_each() -> void:
	if _directory.is_empty() or not DirAccess.dir_exists_absolute(_directory): return
	for name: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)
	_directory = ""

func test_frozen_offer_decimal_samples_survive_actual_file_roundtrip() -> void:
	var records: Array[Dictionary] = []
	records.assign(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/checkpoint_decimal_roundtrip.json")))
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(records), replay.error)
	if not replay.error.is_empty(): return
	var run: RunController = replay.run
	assert_eq(run.state.phase, RunState.Phase.REWARDS)
	var before: Dictionary = RunSnapshot.capture(run)
	_directory = "user://checkpoint-decimal-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var compatibility: Dictionary = RunCheckpointCodec.manifest(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(_directory), compatibility)
	session.rebuild_budget_usec = 10000000
	assert_true(session.save(run).ok)
	var reopened: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(_directory), compatibility)
	reopened.rebuild_budget_usec = 10000000
	var restored: Dictionary = reopened.load_candidate()
	assert_true(restored.ok, restored.reason)
	if restored.ok:
		assert_eq(RunSnapshot.capture(restored.run), before)
		assert_false(restored.fallback)

func test_float_tags_preserve_nested_values_and_signed_zero() -> void:
	var packed: Dictionary = TRANSPORT.encode({"nested": [{"sample": 0.9812430534511805, "zero": -0.0}], "tiny": 5e-324, "large": 1.7976931348623157e308})
	assert_true(packed.ok)
	assert_eq(packed.data.nested[0].zero[TRANSPORT.TAG], "0000000000000080")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(packed.data))
	var decoded: Dictionary = TRANSPORT.decode(parsed)
	assert_true(decoded.ok)
	assert_eq(decoded.data.nested[0].sample, 0.9812430534511805)
	assert_eq(1.0 / decoded.data.nested[0].zero, -INF)
	assert_eq(decoded.data.tiny, 5e-324)
	assert_eq(decoded.data.large, 1.7976931348623157e308)

func test_transport_rejects_reserved_keys_nonfinite_and_invalid_tags() -> void:
	assert_false(TRANSPORT.encode({TRANSPORT.TAG: "literal user key"}).ok)
	assert_false(TRANSPORT.encode({"value": INF}).ok)
	assert_false(TRANSPORT.encode({"value": NAN}).ok)
	for tag: Variant in ["bad", "000000000000f87f", "000000000000f07f", "zzzzzzzzzzzzzzzz", 1]:
		assert_false(TRANSPORT.decode({"value": {TRANSPORT.TAG: tag}}).ok)
	assert_false(TRANSPORT.decode({"value": {TRANSPORT.TAG: "0000000000000000", "extra": true}}).ok)
	assert_false(TRANSPORT.decode({"value": 0.65}).ok)
	assert_false(TRANSPORT.decode({TRANSPORT.TAG: "0000000000000000"}).ok)

func test_v3_root_float_tag_returns_structured_failure() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	_directory = "user://checkpoint-decimal-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var compatibility: Dictionary = RunCheckpointCodec.manifest(run)
	var store: CheckpointStore = CheckpointStore.new(_directory)
	assert_true(store.begin_run(run.state.run_id).ok)
	var package: Dictionary = {"schema": RunCheckpointSession.PACKAGE_SCHEMA, "run_id": run.state.run_id,
		"payload_json": JSON.stringify({TRANSPORT.TAG: "0000000000000000"}), "telemetry": {}}
	assert_true(store.commit(store.stage(package, compatibility)).ok)
	var restored: Dictionary = RunCheckpointSession.new(CheckpointStore.new(_directory), compatibility).load_candidate()
	assert_false(restored.ok)
	assert_eq(restored.reason, "invalid_payload_json")

func test_known_v2_decimal_wrapper_still_reads_without_relaxed_validation() -> void:
	_legacy("run-checkpoint-package-v2")

func test_known_v1_wrapper_still_reads_without_relaxed_validation() -> void:
	_legacy(RunCheckpointCodec.SCHEMA)

func _legacy(schema: String) -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_test", false)
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	assert_true(encoded.ok)
	_directory = "user://checkpoint-decimal-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store: CheckpointStore = CheckpointStore.new(_directory)
	assert_true(store.begin_run(run.state.run_id).ok)
	var package: Dictionary = {"schema": schema, "run_id": run.state.run_id, "payload_json": JSON.stringify(encoded.payload, "", true, true)}
	if schema == "run-checkpoint-package-v2": package["telemetry"] = {}
	assert_true(store.commit(store.stage(package, encoded.manifest)).ok)
	var restored: Dictionary = RunCheckpointSession.new(CheckpointStore.new(_directory), encoded.manifest).load_candidate()
	assert_true(restored.ok, restored.reason)
	if restored.ok: assert_eq(RunSnapshot.capture(restored.run), RunSnapshot.capture(run))
