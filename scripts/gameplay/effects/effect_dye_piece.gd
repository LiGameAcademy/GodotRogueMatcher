extends GameplayEffect
class_name EffectDyePiece

## 染色效果

## 目标颜色（-1 表示随机）
@export var target_color: int = -1

## 染色范围（"adjacent" = 上下左右4格, "neighbor" = 周围8格）
@export var dye_range: String = "adjacent"

## 染色数量
@export var dye_count: int = 1

func _init(color: int = -1, range_type: String = "adjacent", count: int = 1) -> void:
	effect_id = "dye_piece"
	target_color = color
	dye_range = range_type
	dye_count = count

func apply(context: Dictionary = {}) -> bool:
	var board_value: Variant = context.get("board")
	var cell_value: Variant = context.get("item_cell")
	if not board_value is Board or not cell_value is Cell:
		return false
	var board: Board = board_value as Board
	var item_cell: Cell = cell_value as Cell
	
	if not board or not item_cell:
		return false
	
	# 获取目标单元格
	var target_cells: Array[Cell] = []
	if dye_range == "adjacent":
		target_cells = _get_adjacent_cells(board, item_cell.coordinate)
	elif dye_range == "neighbor":
		target_cells = _get_neighbor_cells(board, item_cell.coordinate)
	
	# 筛选出有棋子的单元格
	var valid_cells: Array[Cell] = []
	for cell: Cell in target_cells:
		var snapshot: PieceState = board.rules.state.get_piece_at(cell.coordinate)
		if snapshot != null and snapshot.content_id.is_empty():
			valid_cells.append(cell)
	
	if valid_cells.is_empty():
		return false
	
	# 随机选择目标
	var dyed_count: int = 0
	for i: int in range(min(dye_count, valid_cells.size())):
		var target_cell: Cell = valid_cells[randi() % valid_cells.size()]
		valid_cells.erase(target_cell)
		
		var new_color: int = target_color if target_color >= 0 else randi() % 5
		
		board.set_piece_color(target_cell.coordinate, new_color)
		dyed_count += 1
		
		print("效果 [", effect_id, "] 应用：将棋子染成颜色 ", new_color, " (位置: ", target_cell.coordinate, ")")
	
	return dyed_count > 0

## 获取上下左右4格
func _get_adjacent_cells(board: Board, pos: Vector2i) -> Array[Cell]:
	var adjacent: Array[Cell] = []
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
	]
	for dir: Vector2i in directions:
		var new_pos: Vector2i = Vector2i(pos.x + dir.x, pos.y + dir.y)
		if new_pos.x >= 0 and new_pos.x < board.cols and new_pos.y >= 0 and new_pos.y < board.rows:
			var cell: Cell = board.get_cell(new_pos)
			if cell:
				adjacent.append(cell)
	return adjacent

## 获取周围8格
func _get_neighbor_cells(board: Board, pos: Vector2i) -> Array[Cell]:
	var neighbors: Array[Cell] = []
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var new_pos: Vector2i = Vector2i(pos.x + dx, pos.y + dy)
			if new_pos.x >= 0 and new_pos.x < board.cols and new_pos.y >= 0 and new_pos.y < board.rows:
				var cell: Cell = board.get_cell(new_pos)
				if cell:
					neighbors.append(cell)
	return neighbors

func get_description() -> String:
	var desc: String = "染色 "
	desc += str(dye_count) + " 个棋子"
	if target_color >= 0:
		desc += "为颜色 " + str(target_color)
	else:
		desc += "为随机颜色"
	return desc

