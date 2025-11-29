extends Node

## 寻路管理器（单例）
## 职责：管理 A* 寻路系统

var a_star: AStarGrid2D = AStarGrid2D.new()

## 初始化寻路系统
func initialize(rows: int, cols: int) -> void:
	a_star.region.size = Vector2i(rows, cols)
	# 禁用对角线移动
	a_star.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	a_star.update()

## 更新障碍物
func update_obstacle(coordinate: Vector2i, is_solid: bool) -> void:
	a_star.set_point_solid(coordinate, is_solid)

## 获取路径
func get_chess_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	return a_star.get_point_path(from, to)

## 检查是否有路径
func has_path(from: Vector2i, to: Vector2i) -> bool:
	var path = get_chess_path(from, to)
	return not path.is_empty()
