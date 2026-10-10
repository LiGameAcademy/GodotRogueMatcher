class_name ChoiceEffectContext
extends RefCounted

## 选择效果只获得规则值快照，不获得Game、UI或可写棋盘。
var material: Array[PieceState] = []
var next_refill: int = 0
var color_weights: Array[int] = []
var spawn_config: SpawnConfig
var refill_batches: Dictionary[int, int] = {}
var fuse_ids: Array[int] = []
var upgrades: Dictionary[StringName, int] = {}
var dye_upgrades: Dictionary[StringName, int] = {}
var stage_enabled: bool = false
var goal_bonus_score: int = 0
