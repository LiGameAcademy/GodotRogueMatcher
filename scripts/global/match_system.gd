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
signal match_made(score: int, center_pos: Vector2i, matched_cells: Array[Cell])

## 检查是否有可以消除的棋子
## 返回所有可消除的单元格数组
func check_for_elimination(board: Board, target_cell: Cell) -> Array[Cell]:
	var to_eliminate: Array[Cell] = []
	
	# 检查四个方向：横向、纵向、两个斜向
	var directions: Array[Vector2i] = [
		Vector2i(1, 0),   # 横向
		Vector2i(0, 1),   # 纵向
		Vector2i(1, 1),   # 斜向（左上-右下）
		Vector2i(1, -1)   # 斜向（右上-左下）
	]
	
	for direction: Vector2i in directions:
		var matched: Array[Cell] = check_direction(board, target_cell, direction.x, direction.y)
		if matched.size() >= MIN_MATCH_COUNT:
			# 合并到总数组（去重）
			for cell: Cell in matched:
				if not to_eliminate.has(cell):
					to_eliminate.append(cell)
	
	return to_eliminate

## 检查从给定位置开始的特定方向是否有五个或更多相同的棋子
func check_direction(board: Board, start_cell: Cell, delta_row: int, delta_col: int) -> Array[Cell]:
	if start_cell.piece == null:
		return []  # 如果起始位置为空，则直接返回空数组
	
	var to_eliminate: Array[Cell] = [start_cell]  # 待消除的棋子数组
	var start_type: int = start_cell.piece.piece_type

	for direction: int in [-1, 1]:
		var local_step: int = 1  # 用于跟踪在每个方向上走了多少步
		var can_eliminate: bool = true
		
		while can_eliminate:
			var new_coord: Vector2i = Vector2i(
				start_cell.coordinate.x + local_step * direction * delta_row,
				start_cell.coordinate.y + local_step * direction * delta_col
			)
			
			# 检查边界条件
			if new_coord.x < 0 or new_coord.x >= board.cols or new_coord.y < 0 or new_coord.y >= board.rows:
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
	var to_eliminate: Array[Cell] = check_for_elimination(board, target_cell)
	if not to_eliminate.is_empty():
		await eliminate_and_score(board, to_eliminate)

## 消除并得分
func eliminate_and_score(board: Board, to_eliminate: Array[Cell]) -> void:
	if to_eliminate.is_empty():
		return

	# 计算基础得分
	var base_score: int = calculate_score(to_eliminate.size())

	# 获取消除中心位置
	var center_index: int = int(to_eliminate.size() / 2)
	var center_cell: Cell = to_eliminate[center_index]
	var center_pos: Vector2i = center_cell.coordinate

	# 计算道具加成
	var final_score: int = calculate_item_bonus(board, to_eliminate, base_score)

	# 播放消除动画
	for cell: Cell in to_eliminate:
		if cell.piece:
			cell.piece.eliminate()

	# 等待动画完成
	await board.get_tree().create_timer(0.3).timeout

	# 清除棋子（如果是道具，先注销）
	var effect_system: Node = get_node_or_null("/root/ItemEffectSystem")
	for cell: Cell in to_eliminate:
		if cell.piece and cell.piece.item_data and effect_system:
			effect_system.unregister_item(cell.piece)
		if is_instance_valid(cell.piece):
			var removed_piece: ChessPiece = cell.piece
			cell.piece = null
			removed_piece.queue_free()

	# 更新棋子数量
	GameManager.remove_piece_count(to_eliminate.size())

	# 更新分数（传入加成后的分数）
	GameManager.add_score(final_score)

	# 发出消除信号（效果系统会监听此信号）
	match_made.emit(final_score, center_pos, to_eliminate)

## 计算道具加成
## [param board: Board] 棋盘
## [param matched_cells: Array] 被消除的单元格数组
## [param base_score: int] 基础分数
## [return: int] 加成后的最终分数
func calculate_item_bonus(board: Board, matched_cells: Array, base_score: int) -> int:
	var multiplier: float = 1.0  # 乘法倍率（棱镜塔、以太图腾）
	var bonus: float = 0.0  # 加法加成（增幅器、能量核心）

	# 检测消除涉及的棋子类型
	var has_red_ball: bool = false
	var matched_types: Array[int] = []
	for cell: Cell in matched_cells:
		if cell.piece and cell.piece.item_data == null:  # 是普通棋子，不是道具
			matched_types.append(cell.piece.piece_type)
			if cell.piece.piece_type == 0:  # 0 = 红球
				has_red_ball = true

	# 获取所有已放置的道具
	var placed_items: Array[Cell] = _get_placed_items(board)

	# 计算加成
	for item_cell: Cell in placed_items:
		if not item_cell.piece or not item_cell.piece.item_data:
			continue

		var item_id: String = item_cell.piece.item_data.id

		match item_id:
			"prism_tower":
				# 棱镜塔：参与消除时该次得分 x2
				# 检查棱镜塔是否在消除范围内
				if _is_cell_in_match(item_cell, matched_cells):
					multiplier *= 2.0

			"amplifier":
				# 增幅器：周围8格发生的消除 +100%
				if _is_in_range_8(item_cell.coordinate, matched_cells):
					bonus += 1.0  # +100%

			"ether_totem":
				# 以太图腾：涉及红球的消除得分 x1.5
				if has_red_ball:
					multiplier *= 1.5

			"energy_core":
				# 能量核心：所有消除得分 +50%
				bonus += 0.5  # +50%

	# 综合计算
	var final_score: int = int((base_score * multiplier) + (base_score * bonus))
	return final_score

## 获取棋盘上所有已放置的道具
func _get_placed_items(board: Board) -> Array[Cell]:
	var items: Array[Cell] = []
	for i: int in range(board.rows):
		for j: int in range(board.cols):
			var cell: Cell = board.get_cell(Vector2i(j, i))
			if cell and cell.piece and cell.piece.item_data:
				items.append(cell)
	return items

## 检查道具是否在消除范围内
func _is_cell_in_match(item_cell: Cell, matched_cells: Array[Cell]) -> bool:
	for cell: Cell in matched_cells:
		if cell == item_cell:
			return true
	return false

## 检查道具是否在消除的8格范围内
func _is_in_range_8(item_pos: Vector2i, matched_cells: Array[Cell]) -> bool:
	for cell: Cell in matched_cells:
		var dx: int = abs(cell.coordinate.x - item_pos.x)
		var dy: int = abs(cell.coordinate.y - item_pos.y)
		if dx <= 1 and dy <= 1:
			return true
	return false

## 计算得分
func calculate_score(match_count: int) -> int:
	if match_count <= MIN_MATCH_COUNT:
		return BASE_SCORE * match_count
	else:
		# 基础分 + 连击奖励
		var base_score: int = BASE_SCORE * match_count
		var combo_bonus: int = COMBO_BONUS * (match_count - MIN_MATCH_COUNT) * match_count
		return base_score + combo_bonus
