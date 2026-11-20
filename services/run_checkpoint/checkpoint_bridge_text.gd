extends RefCounted

## Reassembles a bounded browser text transfer under its persistence owner's busy lock.
## No partial text is published; WebFiles still validates the complete opaque snapshot.
const MAX_UNITS: int = 128 * 1024 * 1024
const CHUNK_UNITS: int = 65536

static func receive(metadata: String, pull: Callable, finish: Callable, frame_yield: Callable) -> Dictionary:
	var value: Variant = JSON.parse_string(metadata)
	if not value is Dictionary or value.size() != 2 or not value.get("id") is String:
		finish.call("", 0, true)
		return _failure()
	var id: String = value.id
	if not value.get("units") is float or not is_finite(value.units) or value.units != floor(value.units) or value.units < 0 or value.units > MAX_UNITS:
		finish.call(id, 0, true)
		return _failure()
	var expected: int = int(value.units)
	var units: int = 0
	var index: int = 0
	var chunks: PackedStringArray = []
	var largest: int = 0
	var started: int = Time.get_ticks_usec()
	while units < expected:
		var chunk_started: int = Time.get_ticks_usec()
		var chunk: Variant = pull.call(id, index)
		if not chunk is String or chunk.is_empty() or chunk.length() > CHUNK_UNITS:
			finish.call(id, index, true)
			return _failure()
		var count: int = chunk.to_utf16_buffer().size() / 2
		if count > CHUNK_UNITS or count > expected - units:
			finish.call(id, index, true)
			return _failure()
		units += count
		index += 1
		chunks.append(chunk)
		largest = maxi(largest, Time.get_ticks_usec() - chunk_started)
		if Time.get_ticks_usec() - started >= 2000 or index % 16 == 0:
			await frame_yield.call()
			started = Time.get_ticks_usec()
	if not bool(finish.call(id, index, false)):
		finish.call(id, index, true)
		return _failure()
	var join_started: int = Time.get_ticks_usec()
	var text: String = "".join(chunks)
	return {"ok": true, "reason": "", "data": text, "timing": {"bridge_chunks": index, "largest_bridge_chunk_usec": largest, "bridge_join_usec": Time.get_ticks_usec() - join_started}}

static func _failure() -> Dictionary:
	return {"ok": false, "reason": "web_backend_response_invalid", "data": ""}
