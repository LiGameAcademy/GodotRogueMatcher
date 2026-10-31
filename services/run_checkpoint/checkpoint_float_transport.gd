extends RefCounted

## JSON transport for exact binary64 values, independent of decimal parser rounding.
## The rule payload is unchanged after decoding; this tag belongs only to package v3.
const TAG: String = "$checkpoint_float64"

static func encode(value: Dictionary) -> Dictionary:
	var status: Dictionary = {"ok": true, "reason": ""}
	var data: Variant = _convert(value, false, status, 0)
	return {"ok": status.ok, "reason": status.reason, "data": data}

static func decode(value: Dictionary) -> Dictionary:
	var status: Dictionary = {"ok": true, "reason": ""}
	var data: Variant = _convert(value, true, status, 0)
	if not data is Dictionary:
		status.merge({"ok": false, "reason": "invalid_transport_root"}, true)
	return {"ok": status.ok, "reason": status.reason, "data": data}

## The owner freezes this checkpoint graph. Partial conversion never leaves this operation.
static func encode_checkpoint_sliced(value: Dictionary, frame_yield: Callable) -> Dictionary:
	return await _checkpoint_sliced(value, false, frame_yield)

static func decode_checkpoint_sliced(value: Dictionary, frame_yield: Callable) -> Dictionary:
	return await _checkpoint_sliced(value, true, frame_yield)

static func _checkpoint_sliced(value: Dictionary, reading: bool, frame_yield: Callable) -> Dictionary:
	if not frame_yield.is_valid(): return {"ok": false, "reason": "invalid_step_yield", "data": null}
	if value.has(TAG) or not value.get("records") is Array:
		return decode(value) if reading else encode(value)
	var body: Dictionary = value.duplicate()
	body.erase("records")
	var status: Dictionary = {"ok": true, "reason": ""}
	var started: int = Time.get_ticks_usec()
	var data: Variant = _convert(body, reading, status, 0)
	if not status.ok: return {"ok": false, "reason": status.reason, "data": null}
	var largest: int = Time.get_ticks_usec() - started
	var records: Array = []
	started = Time.get_ticks_usec()
	var count: int = 0
	for row: Variant in value.records:
		# Original graph depths: root 0, records array 1, record 2.
		records.append(_convert(row, reading, status, 2))
		if not status.ok: return {"ok": false, "reason": status.reason, "data": null}
		count += 1
		if count >= 4 or Time.get_ticks_usec() - started >= 2000:
			largest = maxi(largest, Time.get_ticks_usec() - started)
			await frame_yield.call()
			started = Time.get_ticks_usec()
			count = 0
	data["records"] = records
	return {"ok": true, "reason": "", "data": data, "largest_slice_usec": maxi(largest, Time.get_ticks_usec() - started)}

static func _convert(value: Variant, reading: bool, status: Dictionary, depth: int) -> Variant:
	if not status.ok: return null
	if depth > 128:
		status.merge({"ok": false, "reason": "float_transport_depth"}, true)
		return null
	if value is float:
		if reading or not is_finite(value):
			status.merge({"ok": false, "reason": "unencoded_float"}, true)
			return null
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		return {TAG: bytes.hex_encode()}
	if value is Dictionary:
		if value.has(TAG):
			if not reading or value.size() != 1 or not value[TAG] is String or value[TAG].length() != 16:
				status.merge({"ok": false, "reason": "invalid_float_tag"}, true)
				return null
			for character: String in value[TAG]:
				if not character in "0123456789abcdef":
					status.merge({"ok": false, "reason": "invalid_float_tag"}, true)
					return null
			var number: float = String(value[TAG]).hex_decode().decode_double(0)
			if not is_finite(number):
				status.merge({"ok": false, "reason": "nonfinite_float_tag"}, true)
				return null
			return number
		var result: Dictionary = {}
		for key: Variant in value:
			if not key is String:
				status.merge({"ok": false, "reason": "invalid_transport_key"}, true)
				return null
			result[key] = _convert(value[key], reading, status, depth + 1)
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_convert(item, reading, status, depth + 1))
		return result
	if value == null or value is bool or value is int or value is String: return value
	status.merge({"ok": false, "reason": "unsupported_transport_value"}, true)
	return null
