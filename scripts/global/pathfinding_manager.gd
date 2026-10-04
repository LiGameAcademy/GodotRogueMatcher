extends Node

## 寻路管理器（单例）
## 职责：管理 A* 寻路系统

var a_star: AStarGrid2D = AStarGrid2D.new()

## 初始化寻路系统
func initialize(rows: int, cols: int) -> void:
	a_star.region = Rect2i(0, 0, cols, rows)
	# 禁用对角线移动
	a_star.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	a_star.update()
	a_star.fill_solid_region(a_star.region, false)

## 更新障碍物
func update_obstacle(coordinate: Vector2i, is_solid: bool) -> void:
	a_star.set_point_solid(coordinate, is_solid)

## 获取路径
func get_chess_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if not a_star.is_in_boundsv(from) or not a_star.is_in_boundsv(to) or from == to:
		return PackedVector2Array()
	if a_star.is_point_solid(to):
		return PackedVector2Array()
	# 起点被棋子占用；仅在查询期间放行，查询后恢复障碍。
	var was_solid: bool = a_star.is_point_solid(from)
	a_star.set_point_solid(from, false)
	var path: PackedVector2Array = a_star.get_point_path(from, to)
	a_star.set_point_solid(from, was_solid)
	return path

## 检查是否有路径
func has_path(from: Vector2i, to: Vector2i) -> bool:
	var path: PackedVector2Array = get_chess_path(from, to)
	return not path.is_empty()
