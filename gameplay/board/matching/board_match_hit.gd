class_name BoardMatchHit
extends RefCounted

## Frozen geometry of one detection hit. Coordinates align with piece_ids, sorted by entity id.
## origin is a geometric anchor, not the action/skill cause owned by the caller.
var shape_id: StringName = &"line"
var origin: Vector2i = Vector2i.ZERO
var direction: Vector2i = Vector2i.ZERO
var piece_ids: Array[int] = []
var coordinates: Array[Vector2i] = []

func copy() -> BoardMatchHit:
	var result: BoardMatchHit = BoardMatchHit.new()
	result.shape_id = shape_id
	result.origin = origin
	result.direction = direction
	result.piece_ids = piece_ids.duplicate()
	result.coordinates = coordinates.duplicate()
	return result

func data() -> Dictionary:
	return {"shape_id": shape_id, "origin": origin, "direction": direction, "ids": piece_ids.duplicate(), "coordinates": coordinates.duplicate()}
