extends GameplayCondition
class_name ConditionInRange

## 范围内条件

## 范围类型（"adjacent" = 上下左右4格, "neighbor" = 周围8格, "3x3" = 3x3区域）
@export var range_type: String = "neighbor"

## 检查位置（从 context 中获取）
@export var check_position_key: String = "center_pos"

func _init(type: String = "neighbor", position_key: String = "center_pos") -> void:
	condition_id = "in_range"
	range_type = type
	check_position_key = position_key

func check(context: Dictionary = {}) -> bool:
	var board = context.get("board")
	var item_cell = context.get("item_cell")
	var check_pos: Vector2i = context.get(check_position_key, Vector2i(-1, -1))
	
	if not board or not item_cell or check_pos == Vector2i(-1, -1):
		return false
	
	var item_pos = item_cell.coordinate
	
	# 根据范围类型检查
	match range_type:
		"adjacent":
			# 上下左右4格（曼哈顿距离 <= 1 且不在对角）
			var dx = abs(check_pos.x - item_pos.x)
			var dy = abs(check_pos.y - item_pos.y)
			return (dx == 1 and dy == 0) or (dx == 0 and dy == 1)
		"neighbor":
			# 周围8格（包括自己，曼哈顿距离 <= 1）
			var dx = abs(check_pos.x - item_pos.x)
			var dy = abs(check_pos.y - item_pos.y)
			return dx <= 1 and dy <= 1
		"3x3":
			# 3x3区域（包括自己）
			var dx = abs(check_pos.x - item_pos.x)
			var dy = abs(check_pos.y - item_pos.y)
			return dx <= 1 and dy <= 1
	
	return false

func get_description() -> String:
	return "在 " + range_type + " 范围内"

