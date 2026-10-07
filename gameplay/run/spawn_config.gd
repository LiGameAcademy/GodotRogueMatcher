class_name SpawnConfig
extends Resource

## 普通补棋与颜色权重的只读边界；开局数量仍由RunConfig配置。
@export var refill_count: int = 3
@export var minimum_refill: int = 1
@export var maximum_refill: int = 6
@export var color_weights: Array[int] = [4, 4, 4, 4, 4]
@export var minimum_weight: int = 1
@export var maximum_weight: int = 20
