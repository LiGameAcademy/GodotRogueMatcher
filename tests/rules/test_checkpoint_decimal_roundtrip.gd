extends GutTest

## Real normal-play prefix that exposed binary64 loss through the JSON parser.
const TRANSPORT: Script = preload("res://services/run_checkpoint/checkpoint_float_transport.gd")
var _directory: String

func test_sliced_transport_preserves_exact_bytes_and_does_not_mutate_frozen_values() -> void:
	var value: Dictionary = {"records": [], "other": {"tiny": 5e-324}}
	var negative_zero: float = "0000000000000080".hex_decode().decode_double(0)
	assert_eq(1.0 / negative_zero, -INF)
	for index: int in range(130): value.records.append({"sample": 0.9812430534511805, "zero": negative_zero, "index": str(index)})
	var before: Dictionary = value.duplicate(true)
	var frame: int = Engine.get_process_frames()
	var packed: Dictionary = await TRANSPORT.encode_checkpoint_sliced(value, _yield_transport_frame)
	assert_true(packed.ok, packed.reason)
	assert_eq(packed.data.records.back().zero[TRANSPORT.TAG], "0000000000000080")
	assert_gt(Engine.get_process_frames(), frame)
	assert_eq(JSON.stringify(packed.data, "", true, true), JSON.stringify(TRANSPORT.encode(value).data, "", true, true))
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(packed.data))
	var decoded: Dictionary = await TRANSPORT.decode_checkpoint_sliced(parsed, _yield_transport_frame)
	assert_true(decoded.ok, decoded.reason)
	assert_eq(decoded.data, value)
	assert_eq(1.0 / decoded.data.records.back().zero, -INF)
	assert_eq(value, before)

func test_sliced_transport_keeps_depth_tag_and_cycle_rejections() -> void:
	for reading: bool in [false, true]:
		for wraps: int in [124, 125, 126]:
			var row: Dictionary = {"value": {TRANSPORT.TAG: "000000000000e83f"} if reading else 0.75}
			for index: int in range(wraps): row = {"next": row}
			await _compare_transport({"records": [row]}, reading, true)
		var cyclic: Dictionary = {}
		cyclic["self"] = cyclic
		await _compare_transport({"records": [cyclic]}, reading)
		cyclic.clear()
		await _compare_transport({TRANSPORT.TAG: "0000000000000000", "records": []}, reading)
		await _compare_transport({"records": "not_an_array"}, reading)
		var late: Dictionary = {"records": []}
		for index: int in range(20): late.records.append({"value": "valid"})
		late.records.back()["value"] = {TRANSPORT.TAG: "invalid"} if reading else INF
		await _compare_transport(late, reading)
	await _compare_transport({"records": [{"value": 0.65}]}, true)
	await _compare_transport({TRANSPORT.TAG: "0000000000000000"}, true)

func _compare_transport(value: Dictionary, reading: bool, deep_chain: bool = false) -> void:
	var baseline: Dictionary = TRANSPORT.decode(value) if reading else TRANSPORT.encode(value)
	var result: Dictionary
	if reading: result = await TRANSPORT.decode_checkpoint_sliced(value, _yield_transport_frame)
	else: result = await TRANSPORT.encode_checkpoint_sliced(value, _yield_transport_frame)
	assert_eq(result.ok, baseline.ok)
	assert_eq(result.reason, baseline.reason)
	if not baseline.ok or not result.ok: return
	if not deep_chain:
		assert_eq(result.data, baseline.data)
		return
	# GUT/Variant stringify and equality stop at depth100; inspect the known chain iteratively.
	var actual: Dictionary = result.data.records[0]
	var expected: Dictionary = baseline.data.records[0]
	var count: int = 0
	while expected.has("next") and count < 130:
		assert_true(actual.has("next"))
		if not actual.has("next"): return
		actual = actual.next
		expected = expected.next
		count += 1
	assert_eq(actual, expected)

func _yield_transport_frame() -> void:
	await get_tree().process_frame

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
	await _legacy("run-checkpoint-package-v2")

func test_known_v1_wrapper_still_reads_without_relaxed_validation() -> void:
	await _legacy(RunCheckpointCodec.SCHEMA)

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
	var sliced: Dictionary = await RunCheckpointSession.new(CheckpointStore.new(_directory), encoded.manifest).load_candidate_sliced(_yield_transport_frame)
	assert_true(sliced.ok, sliced.reason)
	if sliced.ok: assert_eq(RunSnapshot.capture(sliced.run), RunSnapshot.capture(run))
