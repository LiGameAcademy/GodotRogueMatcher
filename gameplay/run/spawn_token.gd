class_name SpawnToken
extends RefCounted

## 内容提前锁定，落点由出生时的真实空位决定。
var color: int
var core_candidate: bool
var core_color: int

func _init(ordinary_color: int, candidate: bool = false, special_color: int = 1) -> void:
	color = ordinary_color
	core_candidate = candidate
	core_color = special_color

func copy() -> SpawnToken:
	return SpawnToken.new(color, core_candidate, core_color)

func data() -> Dictionary:
	return {"color": color, "core_candidate": core_candidate, "core_color": core_color}
