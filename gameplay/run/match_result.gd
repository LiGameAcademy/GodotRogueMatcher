class_name MatchResult
extends RefCounted

var removed: Array[PieceState] = []
var recolored: Array[PieceState] = []
var previous_colors: Array[int] = []
var source_color: int = -1
var score_entry: ScoreEntry
var cause: StringName = &"match"
var source_id: int = 0
var center: Vector2i = Vector2i.ZERO
var line_axis: int = -1
var radius: int = 0
var cross_radius: int = -1
var generation: int = 0
var followups: Array[Dictionary] = []
## Detached scalar data for recording the trigger snapshot alongside actual hits.
var trigger_strength: Dictionary = {}
