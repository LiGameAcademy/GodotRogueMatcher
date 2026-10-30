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
