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
	piece.piece_type = item_data.base_color
	
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
	if not _can_place_at(board, cell):
		return false
	
	# 创建物品节点（作为特殊棋子）
	var piece: ChessPiece = create_item(item_data)
	if not piece:
		return false
	
	# 放置到单元格（使用 piece 属性，统一处理）
	if not board.place_piece(cell.coordinate, piece):
		piece.free()
		return false
	
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
func _can_place_at(board: Board, cell: Cell) -> bool:
	return board.rules.state.is_valid_coordinate(cell.coordinate) and not board.has_piece(cell.coordinate)

## 获取所有空位
## [param board: Board] 棋盘
## [return: Array[Cell]] 空位数组
func _get_empty_cells(board: Board) -> Array[Cell]:
	return board.get_empty_cells()

## 移除物品
## [param piece: ChessPiece] 棋子节点（可能是道具）
func remove_item(board: Board, piece: ChessPiece) -> void:
	if not piece:
		return
	
	# 使用消除动画（道具和棋子统一处理）
	var snapshot: PieceState = board.rules.state.get_piece(piece.piece_id)
	if snapshot != null:
		board.remove_piece(snapshot.coordinate, true)
