extends RefCounted

## Serializes an already validated, frozen transport graph with Godot's exact JSON bytes.
## Only the large records array is scheduled; no partial text is returned to storage.
static func stringify_checkpoint(value: Dictionary, frame_yield: Callable) -> Dictionary:
	if not frame_yield.is_valid(): return {"ok": false, "reason": "invalid_step_yield"}
	if not value.get("records") is Array: return {"ok": false, "reason": "invalid_records"}
	var keys: Array = value.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray(["{"])
	var started: int = Time.get_ticks_usec()
	var largest: int = 0
	var count: int = 0
	for index: int in range(keys.size()):
		var key: String = keys[index]
		if index > 0: parts.append(",")
		parts.append(JSON.stringify(key) + ":")
		if key != "records":
			parts.append(JSON.stringify(value[key], "", true, true))
			continue
		parts.append("[")
		var rows: Array = value.records
		for row_index: int in range(rows.size()):
			if row_index > 0: parts.append(",")
			parts.append(JSON.stringify(rows[row_index], "", true, true))
			count += 1
			if count >= 64 or Time.get_ticks_usec() - started >= 2000:
				largest = maxi(largest, Time.get_ticks_usec() - started)
				await frame_yield.call()
				started = Time.get_ticks_usec()
				count = 0
		parts.append("]")
	parts.append("}")
	var text: String = "".join(parts)
	return {"ok": true, "reason": "", "text": text, "largest_slice_usec": maxi(largest, Time.get_ticks_usec() - started)}
