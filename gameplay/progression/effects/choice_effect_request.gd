class_name ChoiceEffectRequest
extends RefCounted

enum Kind { REFILL, COLOR_WEIGHT, CLEAR, UPGRADE, DYE_UPGRADE, DYE, GOAL_BONUS, UNLOCK_CORE, UNLOCK_LINE, ASSIGN_FUSE, DEMOLITION_STAT, THIN, LINE_UPGRADE }
var coordinate: Vector2i = Vector2i(-1, -1)
var score_bonus: int = 0
var score_cleared: bool = false
var upgrade: StringName
var kind: Kind = Kind.REFILL
var error: String = ""
var delta: int = 0
var batches: int = 0
var color: int = -1
var piece_ids: Array[int] = []
var stat: int = 0
