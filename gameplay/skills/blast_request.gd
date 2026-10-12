class_name BlastRequest
extends RefCounted

## 爆炸队列项。可携带分发票据，或表示合成余震。
var synthetic: bool = false
var source: PieceState
var ability: AbilityInstance
var activation: AbilityActivation
var generation: int = 0
var radius: int = 0
var target_ids: Array[int] = []
