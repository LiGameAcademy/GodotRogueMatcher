extends GutTest

const CHECKPOINT_JSON: Script = preload("res://services/run_checkpoint/checkpoint_json.gd")
const TRANSPORT: Script = preload("res://services/run_checkpoint/checkpoint_float_transport.gd")

func test_sliced_json_has_identical_sorted_utf8_bytes_without_mutating_values() -> void:
	var value: Dictionary = {"中文": "\n\t\r\b\f\"\\", "records": [], "a": {"z": 0.1, "a": null}, "Z": true}
	for index: int in range(130):
		value.records.append({"text": "开心果😀", "index": str(index), "values": [0.25, false, null]})
	var transported: Dictionary = TRANSPORT.encode(value)
	var before: Dictionary = transported.data.duplicate(true)
	var frame: int = Engine.get_process_frames()
	var result: Dictionary = await CHECKPOINT_JSON.stringify_checkpoint(transported.data, _yield_frame)
	assert_true(result.ok)
	assert_gt(Engine.get_process_frames(), frame)
	assert_eq(result.text.to_utf8_buffer(), JSON.stringify(transported.data, "", true, true).to_utf8_buffer())
	assert_eq(transported.data, before)
	var empty: Dictionary = await CHECKPOINT_JSON.stringify_checkpoint({"records": []}, _yield_frame)
	assert_eq(empty.text, "{\"records\":[]}")
	assert_eq((await CHECKPOINT_JSON.stringify_checkpoint({}, _yield_frame)).reason, "invalid_records")
	assert_eq((await CHECKPOINT_JSON.stringify_checkpoint(value, Callable())).reason, "invalid_step_yield")

func test_real_package_sliced_and_sync_bytes_match_before_independent_readback() -> void:
	var records: Array[Dictionary] = []
	records.assign(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/checkpoint_decimal_roundtrip.json")))
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(records), replay.error)
	if replay.run == null: return
	var encoded: Dictionary = RunCheckpointCodec.encode(replay.run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new("memory://json-only"), encoded.manifest)
	var baseline: Dictionary = session._prepare_package(encoded)
	var sliced: Dictionary = await session._prepare_package_sliced(encoded, _yield_frame)
	assert_true(sliced.ok, sliced.reason)
	assert_eq(sliced.package, baseline.package)
	assert_eq(JSON.stringify(sliced.package).to_utf8_buffer(), JSON.stringify(baseline.package).to_utf8_buffer())
	var roundtrip: Dictionary = await session._roundtrip_package_sliced(sliced.package, _yield_frame)
	assert_true(roundtrip.ok, roundtrip.reason)
	assert_eq(roundtrip.data, encoded.payload)

func _yield_frame() -> void:
	await get_tree().process_frame
