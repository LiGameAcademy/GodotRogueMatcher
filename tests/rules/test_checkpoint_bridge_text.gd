extends GutTest

## Checks chunk identity, Unicode length and fail-closed reconstruction.
const TEXT: Script = preload("res://services/run_checkpoint/checkpoint_bridge_text.gd")

func test_reassembles_unicode_and_yields_without_publishing_partial_text() -> void:
	var source: String = ("a".repeat(65534) + "😀中文").repeat(18)
	var chunks: PackedStringArray = []
	for offset: int in range(0, source.length(), 20000): chunks.append(source.substr(offset, 20000))
	var observed: Array[int] = [0, 0]
	var pull: Callable = func(id: String, index: int) -> Variant:
		assert_eq(id, "transfer")
		assert_eq(index, observed[0])
		observed[0] += 1
		return chunks[index]
	var finish: Callable = func(id: String, count: int, cancel: bool) -> bool:
		assert_eq(id, "transfer")
		assert_false(cancel)
		return count == chunks.size()
	var between: Callable = func() -> void:
		observed[1] += 1
		await get_tree().process_frame
	var result: Dictionary = await TEXT.receive(JSON.stringify({"id": "transfer", "units": source.to_utf16_buffer().size() / 2}), pull, finish, between)
	assert_true(result.ok)
	assert_eq(result.data, source)
	assert_gt(observed[1], 0)

func test_rejects_truncated_overlong_wrong_type_and_failed_final_confirmation() -> void:
	for part: Variant in ["", null, 42, "abcd", "a".repeat(65537)]:
		var cancelled: Array[bool] = []
		var pull: Callable = func(_id: String, _index: int) -> Variant: return part
		var finish: Callable = func(_id: String, _index: int, cancel: bool) -> bool:
			cancelled.append(cancel)
			return false
		var result: Dictionary = await TEXT.receive('{"id":"x","units":3}', pull, finish, _yield_frame)
		assert_false(result.ok)
		assert_eq(result.data, "")
		assert_eq(cancelled, [true])
	var result: Dictionary = await TEXT.receive('{"id":"x","units":1}', func(_id: String, _index: int) -> Variant: return "a", func(_id: String, _index: int, _cancel: bool) -> bool: return false, _yield_frame)
	assert_false(result.ok)

func test_rejects_invalid_transfer_sizes_before_pulling() -> void:
	for size: Variant in [-1, 1.5, TEXT.MAX_UNITS + 1, "3", null]:
		var calls: Array[int] = [0]
		var pull: Callable = func(_id: String, _index: int) -> Variant:
			calls[0] += 1
			return "unexpected"
		var result: Dictionary = await TEXT.receive(JSON.stringify({"id": "x", "units": size}), pull, func(_id: String, _index: int, _cancel: bool) -> bool: return false, _yield_frame)
		assert_false(result.ok)
		assert_eq(calls[0], 0)

func _yield_frame() -> void:
	await get_tree().process_frame
