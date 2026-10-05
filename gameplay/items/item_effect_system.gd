extends Node

## 道具效果系统（单例）
## 职责：管理所有道具效果的触发和执行

## 触发时机枚举
enum TriggerTiming {
	ON_PLACE,      # 放置时
	ON_TURN_START, # 回合开始
	ON_TURN_END,   # 回合结束
	ON_MATCH,      # 消除时
	ON_MOVE        # 移动时
}

## 已放置的道具列表（ChessPiece 节点，包含 ItemData）
var placed_items: Array[ChessPiece] = []

func _ready() -> void:
	# 连接游戏信号
	_connect_game_signals()

## 连接游戏信号
func _connect_game_signals() -> void:
	# 连接回合信号
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.turn_ended.connect(_on_turn_ended)
	
	# 连接消除信号
	MatchSystem.match_made.connect(_on_match_made)

## 注册道具（当道具被放置到棋盘时调用）
## [param piece: ChessPiece] 道具棋子节点
func register_item(piece: ChessPiece) -> void:
	if not piece or not piece.item_data:
		return
	
	# 检查是否已注册
	if placed_items.has(piece):
		return
	
	placed_items.append(piece)
	
	# 检查效果配置是否存在
	var item_data = piece.item_data
	if not item_data.effect_config:
		push_warning("道具 " + item_data.id + " 没有配置效果！")
		return
	
	# 触发放置时效果
	_trigger_effect(piece, TriggerTiming.ON_PLACE)

## 注销道具（当道具被移除时调用）
## [param piece: ChessPiece] 道具棋子节点
func unregister_item(piece: ChessPiece) -> void:
	if placed_items.has(piece):
		placed_items.erase(piece)

## 回合开始回调
func _on_turn_started(_turn_count: int) -> void:
	_trigger_effects_for_timing(TriggerTiming.ON_TURN_START)

## 回合结束回调
func _on_turn_ended(_turn_count: int) -> void:
	_trigger_effects_for_timing(TriggerTiming.ON_TURN_END)

## 消除回调
## [param score: int] 消除得分
## [param center_pos: Vector2i] 消除中心位置
## [param matched_cells: Array] 被消除的单元格数组
func _on_match_made(score: int, center_pos: Vector2i, matched_cells: Array) -> void:
	# 检查消除范围内的道具
	var board = get_tree().get_first_node_in_group("board")
	if not board:
		return
	
	# 获取消除中心周围的单元格（8格）
	var affected_items: Array[ChessPiece] = []
	for cell in matched_cells:
		if cell is Cell:
			var cell_obj = cell as Cell
			# 检查周围8格是否有道具
			var neighbors = _get_neighbor_cells(board, cell_obj.coordinate)
			for neighbor in neighbors:
				if neighbor.piece and neighbor.piece.item_data:
					if not affected_items.has(neighbor.piece):
						affected_items.append(neighbor.piece)
	
	# 触发消除时效果
	for item in affected_items:
		_trigger_effect(item, TriggerTiming.ON_MATCH, {
			"score": score,
			"center_pos": center_pos,
			"matched_cells": matched_cells
		})

## 触发指定时机的所有效果
## [param timing: TriggerTiming] 触发时机
func _trigger_effects_for_timing(timing: TriggerTiming) -> void:
	for item in placed_items:
		if is_instance_valid(item) and item.item_data:
			_trigger_effect(item, timing)

## 触发道具效果
## [param piece: ChessPiece] 道具棋子节点
## [param timing: TriggerTiming] 触发时机
## [param context: Dictionary] 上下文数据（可选）
func _trigger_effect(piece: ChessPiece, timing: TriggerTiming, context: Dictionary = {}) -> void:
	if not piece or not piece.item_data:
		return
	
	var item_data = piece.item_data
	
	# 检查效果配置是否存在
	if not item_data.effect_config:
		push_warning("道具 " + item_data.id + " 没有配置效果！")
		return
	
	var config: ItemEffectConfig = item_data.effect_config
	if not config:
		return
	
	# 构建上下文数据
	var full_context = context.duplicate()
	full_context["timing"] = timing
	full_context["board"] = get_tree().get_first_node_in_group("board")
	full_context["item_cell"] = _get_cell_for_piece(full_context["board"], piece)
	full_context["piece"] = piece
	
	# 应用效果（会自动检查条件）
	config.apply_effects(full_context)

## ========== 旧代码已移除，使用新的效果系统 ==========

## ========== 辅助方法 ==========

## 获取棋子所在的单元格
## [param board: Board] 棋盘
## [param piece: ChessPiece] 棋子节点
## [return: Cell] 单元格，如果未找到返回 null
func _get_cell_for_piece(board: Board, piece: ChessPiece) -> Cell:
	for i in range(board.rows):
		for j in range(board.cols):
			var cell = board.get_cell(Vector2i(j, i))
			if cell and cell.piece == piece:
				return cell
	return null

## 获取周围8格（包括自己）
## [param board: Board] 棋盘
## [param pos: Vector2i] 中心位置
## [return: Array[Cell]] 周围单元格数组
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

## 获取上下左右4格
## [param board: Board] 棋盘
## [param pos: Vector2i] 中心位置
## [return: Array[Cell]] 相邻单元格数组
func _get_adjacent_cells(board: Board, pos: Vector2i) -> Array[Cell]:
	var adjacent: Array[Cell] = []
	var directions = [
		Vector2i(0, -1),  # 上
		Vector2i(0, 1),   # 下
		Vector2i(-1, 0),  # 左
		Vector2i(1, 0)    # 右
	]
	
	for dir in directions:
		var new_pos = Vector2i(pos.x + dir.x, pos.y + dir.y)
		if new_pos.x >= 0 and new_pos.x < board.cols and new_pos.y >= 0 and new_pos.y < board.rows:
			var cell = board.get_cell(new_pos)
			if cell:
				adjacent.append(cell)
	
	return adjacent

