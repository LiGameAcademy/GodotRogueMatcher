class_name BlastRequest
extends RefCounted

var synthetic: bool = false

var source: PieceState
var ability: AbilityInstance
var activation: AbilityActivation
var generation: int = 0
var radius: int = 0
var target_ids: Array[int] = []
