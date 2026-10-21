class_name MatchShapeTemplate
extends Resource

const MAXIMUM_OFFSET: int = 64
const MAXIMUM_CELLS: int = 4096

## Read-only detection configuration; enabling a prototype is not acquiring a skill.
@export var shape_id: StringName
@export var offsets: Array[Vector2i] = []

func validation_error() -> String:
	if shape_id.is_empty() or shape_id == &"line": return "missing or reserved shape identity"
	if offsets.is_empty(): return "template has no required cells"
	if offsets.size() > MAXIMUM_CELLS: return "too many required cells"
	var seen: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		if offset.x < -MAXIMUM_OFFSET or offset.x > MAXIMUM_OFFSET or offset.y < -MAXIMUM_OFFSET or offset.y > MAXIMUM_OFFSET: return "required cell outside supported bounds"
		if seen.has(offset): return "duplicate required cell"
		seen.append(offset)
	return ""

## Records contain scalar configuration only; never load scripts or Resource paths from JSON.
static func from_record(value: Variant) -> MatchShapeTemplate:
	if not value is Dictionary: return null
	var fields: Dictionary = value
	if fields.size() != 2 or not fields.get("shape_id") is String or not fields.get("offsets") is Array: return null
	var cells: Array = fields.offsets
	if cells.is_empty() or cells.size() > MAXIMUM_CELLS: return null
	var result: MatchShapeTemplate = MatchShapeTemplate.new()
	result.shape_id = StringName(fields.shape_id)
	for cell: Variant in cells:
		if not cell is Array or cell.size() != 2: return null
		if not CommandCodec.valid_integer(cell[0]) or not CommandCodec.valid_integer(cell[1]): return null
		var x: int = String(cell[0]).to_int()
		var y: int = String(cell[1]).to_int()
		if x < -MAXIMUM_OFFSET or x > MAXIMUM_OFFSET or y < -MAXIMUM_OFFSET or y > MAXIMUM_OFFSET: return null
		result.offsets.append(Vector2i(x, y))
	return result if result.validation_error().is_empty() else null

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
