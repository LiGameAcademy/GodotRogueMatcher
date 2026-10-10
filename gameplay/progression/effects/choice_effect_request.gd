class_name ChoiceEffectRequest
extends RefCounted

enum Kind { REFILL, COLOR_WEIGHT, CLEAR, UPGRADE, DYE_UPGRADE, DYE, GOAL_BONUS }
var score_bonus: int = 0
var upgrade: StringName
var kind: Kind = Kind.REFILL
var error: String = ""
var delta: int = 0
var batches: int = 0
var color: int = -1
var piece_ids: Array[int] = []
