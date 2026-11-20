extends RefCounted

## Strict pure-value helpers for the explicit snapshot field mappings; no saved property paths.
static func integer(value: Variant, minimum: int = -9223372036854775807, maximum: int = 9223372036854775807) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value and value.to_int() >= minimum and value.to_int() <= maximum

static func keys(value: Variant, required: PackedStringArray) -> bool:
	if not value is Dictionary or value.size() != required.size(): return false
	for key: String in required:
		if not value.has(key): return false
	return true

static func ints(values: Variant, minimum: int = 0, maximum: int = 9223372036854775807) -> bool:
	if not values is Array: return false
	for value: Variant in values:
		if not integer(value, minimum, maximum): return false
	return true

static func int_map(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: Variant in value:
		if not key is String or key.is_empty() or not integer(value[key], 0): return false
	return true

static func names(value: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for key: String in value: result[StringName(key)] = String(value[key]).to_int()
	return result

## Field names below are code-owned constants; never supplied by a saved document.
static func scalars(target: Object, data: Dictionary, fields: Dictionary) -> bool:
	for key: String in fields:
		if not data.has(key): return false
		var property: String = fields[key]
		var expected: Variant = target.get(property)
		var value: Variant = data[key]
		match typeof(expected):
			TYPE_INT:
				if not integer(value): return false
				target.set(property, String(value).to_int())
			TYPE_BOOL:
				if not value is bool: return false
				target.set(property, value)
			TYPE_STRING_NAME:
				if not value is String: return false
				target.set(property, StringName(value))
			_:
				return false
	return true
