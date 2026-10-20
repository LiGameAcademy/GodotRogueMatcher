class_name BlastRequest
extends RefCounted

## Removal queue item for blasts and line sweeps; may represent a synthetic aftershock.
var synthetic: bool = false
var source: PieceState
var ability: AbilityInstance
var activation: AbilityActivation
var generation: int = 0
var radius: int = 0
## -1 means single-axis sweep; otherwise the perpendicular band radius.
var cross_radius: int = -1
var target_ids: Array[int] = []
