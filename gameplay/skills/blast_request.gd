class_name BlastRequest
extends RefCounted

## Blast queue item. May carry a dispatch ticket or represent a synthetic aftershock.
var synthetic: bool = false
var source: PieceState
var ability: AbilityInstance
var activation: AbilityActivation
var generation: int = 0
var radius: int = 0
var target_ids: Array[int] = []
