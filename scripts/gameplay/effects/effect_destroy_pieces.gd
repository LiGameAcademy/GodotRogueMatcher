extends GameplayEffect
class_name EffectDestroyPieces

## 摧毁棋子效果

## 摧毁范围类型（"3x3", "adjacent", "neighbor"）
@export var destroy_range: String = "3x3"

## 是否摧毁道具
@export var destroy_items: bool = false

func _init(range_type: String = "3x3", items: bool = false) -> void:
	effect_id = "destroy_pieces"
	destroy_range = range_type
	destroy_items = items

func apply(context: Dictionary = {}) -> bool:
	var board = context.get("board")
	var item_cell = context.get("item_cell")
	
	if not board or not item_cell:
		return false
	
	# 获取目标单元格
	var target_cells: Array[Cell] = []
	match destroy_range:
		"3x3":
			target_cells = _get_3x3_cells(board, item_cell.coordinate)
		"adjacent":
			target_cells = _get_adjacent_cells(board, item_cell.coordinate)
		"neighbor":
			target_cells = _get_neighbor_cells(board, item_cell.coordinate)
	
	# 摧毁棋子
	var destroyed_count: int = 0
	for cell in target_cells:
		if cell.piece:
			# 检查是否摧毁道具
			if cell.piece.item_data and not destroy_items:
				continue
			
			# 如果是道具，先注销
			if cell.piece.item_data:
				ItemEffectSystem.unregister_item(cell.piece)
			
			# 播放消除动画
			cell.piece.eliminate()
			
			# 清除棋子（不等待动画，异步处理）
			var piece_to_remove = cell.piece
			cell.piece = null
			destroyed_count += 1
			
			# 更新棋子数量
			GameManager.remove_piece_count(1)
			
			# 延迟删除节点（让动画播放）
			if is_instance_valid(piece_to_remove):
				piece_to_remove.queue_free()
	
	print("效果 [", effect_id, "] 应用：摧毁 ", destroyed_count, " 个棋子")
	return destroyed_count > 0

## 获取3x3区域
func _get_3x3_cells(board: Board, pos: Vector2i) -> Array[Cell]:
	var cells: Array[Cell] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var new_pos = Vector2i(pos.x + dx, pos.y + dy)
			if new_pos.x >= 0 and new_pos.x < board.cols and new_pos.y >= 0 and new_pos.y < board.rows:
				var cell = board.get_cell(new_pos)
				if cell:
					cells.append(cell)
	return cells

## 获取上下左右4格
func _get_adjacent_cells(board: Board, pos: Vector2i) -> Array[Cell]:
	var adjacent: Array[Cell] = []
	var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for dir in directions:
		var new_pos = Vector2i(pos.x + dir.x, pos.y + dir.y)
		if new_pos.x >= 0 and new_pos.x < board.cols and new_pos.y >= 0 and new_pos.y < board.rows:
			var cell = board.get_cell(new_pos)
			if cell:
				adjacent.append(cell)
	return adjacent

## 获取周围8格
func _get_neighbor_cells(board: Board, pos: Vector2i) -> Array[Cell]:
	var neighbors: Array[Cell] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var new_pos = Vector2i(pos.x + dx, pos.y + dy)
			if new_pos.x >= 0 and new_pos.x < board.cols and new_pos.y >= 0 and new_pos.y < board.rows:
				var cell = board.get_cell(new_pos)
				if cell:
					neighbors.append(cell)
	return neighbors

func get_description() -> String:
	return "摧毁 " + destroy_range + " 区域的棋子"

