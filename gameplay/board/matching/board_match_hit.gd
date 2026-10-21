class_name BoardMatchHit
extends RefCounted

## Frozen geometry of one detection hit. Coordinates align with piece_ids, sorted by entity id.
## origin is a geometric anchor, not the action/skill cause owned by the caller.
var shape_id: StringName = &"line"
var origin: Vector2i = Vector2i.ZERO
var direction: Vector2i = Vector2i.ZERO
var piece_ids: Array[int] = []
var coordinates: Array[Vector2i] = []
