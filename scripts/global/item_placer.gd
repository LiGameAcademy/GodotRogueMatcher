extends Node

## 物品放置管理器（单例）
## 职责：根据 ItemData 创建物品节点（作为特殊棋子）

## ChessPiece 场景资源
const CHESS_PIECE_SCENE: PackedScene = preload("res://prefabs/chess_piece.tscn")

## 创建物品节点（作为特殊棋子）
## [param item_data: ItemData] 物品数据
## [return: ChessPiece] 创建的物品节点（ChessPiece 类型）
func create_item(item_data: ItemData) -> ChessPiece:
	if not item_data:
		print("错误：ItemData 为空，无法创建物品")
		return null
	
	# 实例化 ChessPiece 场景（道具视为特殊棋子）
	var piece: ChessPiece = CHESS_PIECE_SCENE.instantiate() as ChessPiece
	if not piece:
		print("错误：无法实例化 ChessPiece 场景")
		return null
	
	# 初始化物品（将道具数据设置到棋子上）
	piece.initialize_item(item_data)
	
	return piece

## 在棋盘上放置物品（自动选择随机空位）
## [param board: Board] 棋盘
## [param item_data: ItemData] 物品数据
## [return: bool] 是否成功放置
func place_item_randomly(board: Board, item_data: ItemData) -> bool:
	if not board or not item_data:
		return false
	
	# 获取所有空位
	var empty_cells: Array[Cell] = _get_empty_cells(board)
	if empty_cells.is_empty():
		print("警告：没有空位放置物品")
		return false
	
	# 随机选择空位
	var random_index: int = randi() % empty_cells.size()
	var cell: Cell = empty_cells[random_index]
	
	# 放置物品
	return place_item_at(board, cell, item_data)

## 在指定位置放置物品
## [param board: Board] 棋盘
## [param cell: Cell] 目标单元格
## [param item_data: ItemData] 物品数据
## [return: bool] 是否成功放置
func place_item_at(board: Board, cell: Cell, item_data: ItemData) -> bool:
	if not board or not cell or not item_data:
		return false
	
	# 检查位置是否可用
	if not _can_place_at(cell, item_data):
		return false
	
	# 创建物品节点（作为特殊棋子）
	var piece: ChessPiece = create_item(item_data)
	if not piece:
		return false
	
	# 放置到单元格（使用 piece 属性，统一处理）
	cell.piece = piece
	piece.position = Vector2.ZERO
	GameManager.add_piece_count(1)
	
	# 播放出现动画
	piece.spawn_animation()
	
	# 如果是道具，注册到效果系统
	if piece.item_data:
		var effect_system: Node = get_node_or_null("/root/ItemEffectSystem")
		if effect_system:
			effect_system.register_item(piece)
	
	return true

## 检查是否可以放置在指定位置
## [param cell: Cell] 目标单元格
## [param item_data: ItemData] 物品数据
## [return: bool] 是否可以放置
func _can_place_at(cell: Cell, item_data: ItemData) -> bool:
	if not cell or not item_data:
		return false
	
	# 检查是否有棋子（如果物品占用空间，不能放在有棋子的位置）
	if item_data.occupies_space and cell.piece != null:
		return false
	
	# TODO: 检查放置规则（如 BAD_SECTOR_ONLY）
	# for rule in item_data.placement_rules:
	#     if not _check_placement_rule(cell, rule):
	#         return false
	
	return true

## 获取所有空位
## [param board: Board] 棋盘
## [return: Array[Cell]] 空位数组
func _get_empty_cells(board: Board) -> Array[Cell]:
	var empty_cells: Array[Cell] = []
	
	# 遍历所有单元格
	for i: int in range(board.rows):
		for j: int in range(board.cols):
			var cell: Cell = board.get_cell(Vector2i(j, i))
			if cell and cell.piece == null:
				empty_cells.append(cell)
	
	return empty_cells

## 移除物品
## [param piece: ChessPiece] 棋子节点（可能是道具）
func remove_item(piece: ChessPiece) -> void:
	if not piece:
		return
	
	# 使用消除动画（道具和棋子统一处理）
	var cell: Cell = piece.get_parent() as Cell
	await piece.eliminate()
	if is_instance_valid(cell) and cell.piece == piece:
		cell.piece = null
		GameManager.remove_piece_count(1)
	ItemEffectSystem.unregister_item(piece)
	piece.queue_free()
