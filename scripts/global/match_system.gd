extends Node

## 消除系统（单例）
## 职责：处理消除检测和消除逻辑

## 最小消除数量
const MIN_MATCH_COUNT: int = 5

## 基础分数
const BASE_SCORE: int = 10

## 连击奖励（每多一个棋子额外分数）
const COMBO_BONUS: int = 2

# 信号
## 消除完成
signal match_made(score: int, center_pos: Vector2i, matched_cells: Array)

## 检查是否有可以消除的棋子
## 返回所有可消除的单元格数组
func check_for_elimination(board: Board, target_cell: Cell) -> Array[Cell]:
	var to_eliminate: Array[Cell] = []
	
	# 检查四个方向：横向、纵向、两个斜向
	var directions = [
		Vector2i(1, 0),   # 横向
		Vector2i(0, 1),   # 纵向
		Vector2i(1, 1),   # 斜向（左上-右下）
		Vector2i(1, -1)   # 斜向（右上-左下）
	]
	
	for direction in directions:
		var matched = check_direction(board, target_cell, direction.x, direction.y)
		if matched.size() >= MIN_MATCH_COUNT:
			# 合并到总数组（去重）
			for cell in matched:
				if not to_eliminate.has(cell):
					to_eliminate.append(cell)
	
	return to_eliminate

## 检查从给定位置开始的特定方向是否有五个或更多相同的棋子
func check_direction(board: Board, start_cell: Cell, delta_row: int, delta_col: int) -> Array[Cell]:
	if start_cell.piece == null:
		return []  # 如果起始位置为空，则直接返回空数组
	
	var to_eliminate: Array[Cell] = [start_cell]  # 待消除的棋子数组
	var start_type = start_cell.piece.piece_type

	for direction in [-1, 1]:
		var local_step = 1  # 用于跟踪在每个方向上走了多少步
		var can_eliminate = true
		
		while can_eliminate:
			var new_coord = Vector2i(
				start_cell.coordinate.x + local_step * direction * delta_row,
				start_cell.coordinate.y + local_step * direction * delta_col
			)
			
			# 检查边界条件
			if new_coord.x < 0 or new_coord.x >= board.rows or new_coord.y < 0 or new_coord.y >= board.cols:
				break
			
			var new_cell: Cell = board.get_cell(new_coord)
			if new_cell.piece == null:
				break
			
			if new_cell.piece.piece_type == start_type:
				if not to_eliminate.has(new_cell):
					to_eliminate.append(new_cell)
				local_step += 1  # 更新步数
			else:
				can_eliminate = false
	
	return to_eliminate

## 检查并消除（便捷方法）
func check_and_eliminate(board: Board, target_cell: Cell) -> void:
	var to_eliminate = check_for_elimination(board, target_cell)
	if not to_eliminate.is_empty():
		await eliminate_and_score(board, to_eliminate)

## 消除并得分
func eliminate_and_score(board: Board, to_eliminate: Array[Cell]) -> void:
	if to_eliminate.is_empty():
		return
	
	# 计算得分
	var total_score = calculate_score(to_eliminate.size())
	
	# 获取消除中心位置
	var center_index = float(to_eliminate.size()) / 2
	var center_cell: Cell = to_eliminate[center_index]
	var center_pos = center_cell.coordinate
	
	# 播放消除动画
	for cell in to_eliminate:
		if cell.piece:
			cell.piece.eliminate()
	
	# 等待动画完成
	await board.get_tree().create_timer(0.3).timeout
	
	# 清除棋子（如果是道具，先注销）
	var effect_system = get_node_or_null("/root/ItemEffectSystem")
	for cell in to_eliminate:
		if cell.piece and cell.piece.item_data and effect_system:
			effect_system.unregister_item(cell.piece)
		cell.piece = null
	
	# 更新棋子数量
	GameManager.remove_piece_count(to_eliminate.size())
	
	# 更新分数
	GameManager.add_score(total_score)
	
	# 发出消除信号（效果系统会监听此信号）
	match_made.emit(total_score, center_pos, to_eliminate)

## 计算得分
func calculate_score(match_count: int) -> int:
	if match_count <= MIN_MATCH_COUNT:
		return BASE_SCORE * match_count
	else:
		# 基础分 + 连击奖励
		var base_score = BASE_SCORE * match_count
		var combo_bonus = COMBO_BONUS * (match_count - MIN_MATCH_COUNT) * match_count
		return base_score + combo_bonus
