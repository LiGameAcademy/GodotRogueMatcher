class_name MatchShapeTemplate
extends Resource

## Read-only detection configuration; enabling a prototype is not acquiring a skill.
@export var shape_id: StringName
@export var offsets: Array[Vector2i] = []

func validation_error() -> String:
	if shape_id.is_empty() or shape_id == &"line": return "missing or reserved shape identity"
	if offsets.is_empty(): return "template has no required cells"
	var seen: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		if seen.has(offset): return "duplicate required cell"
		seen.append(offset)
	return ""

func variants() -> Array[MatchShapeTemplate]:
	var result: Array[MatchShapeTemplate] = []
	var seen: Dictionary[String, bool] = {}
	var error: String = validation_error()
	if not error.is_empty():
		push_error("invalid match template: " + error)
		return result
	for mirror: bool in [false, true]:
		for rotation: int in range(4):
			var transformed: Array[Vector2i] = []
			var minimum: Vector2i = Vector2i(2147483647, 2147483647)
			for source: Vector2i in offsets:
				var point: Vector2i = Vector2i(-source.x, source.y) if mirror else source
				for turn: int in range(rotation): point = Vector2i(-point.y, point.x)
				transformed.append(point)
				minimum = Vector2i(mini(minimum.x, point.x), mini(minimum.y, point.y))
			for index: int in range(transformed.size()): transformed[index] -= minimum
			transformed.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
			var key: String = str(transformed)
			if seen.has(key): continue
			seen[key] = true
			var variant: MatchShapeTemplate = MatchShapeTemplate.new()
			variant.shape_id = shape_id
			variant.offsets = transformed
			result.append(variant)
	return result
