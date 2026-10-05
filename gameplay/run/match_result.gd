class_name MatchResult
extends RefCounted

var removed: Array[PieceState] = []
var score_entry: ScoreEntry
var cause: StringName = &"match"
var source_id: int = 0
var center: Vector2i = Vector2i.ZERO
var radius: int = 0
var generation: int = 0
