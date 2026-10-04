extends Node

## 生成管理器（单例）
## 职责：管理棋子的生成逻辑

## 每次生成的棋子数量
const SPAWN_COUNT: int = 3

## 棋子类型数量
const PIECE_TYPE_COUNT: int = 5

## 棋子预制体
var s_piece: PackedScene = preload("res://prefabs/chess_piece.tscn")

## 生成随机棋子
## [param board: Board] 棋盘
## [return] 成功生成的棋子数量
func spawn_random_pieces(board: Board) -> int:
	var max_pieces = board.rows * board.cols
	var current_count = GameManager.piece_count

	# 检查是否有足够空间
	if max_pieces - current_count <= SPAWN_COUNT:
		GameManager.check_game_over()
		return 0

	var spawned_count = 0
	for i in range(SPAWN_COUNT):
		if spawn_piece(board):
			spawned_count += 1
			GameManager.add_piece_count(1)
		else:
			print("警告：无法生成棋子 ", i + 1, "/", SPAWN_COUNT)

	print("生成棋子完成：成功 ", spawned_count, "/", SPAWN_COUNT)
	return spawned_count

## 在指定位置生成一个随机的棋子
## [param board: Board] 棋盘
## [param coordinate: Vector2i] 指定坐标
## [return] 是否成功生成
func spawn_piece(board: Board, coordinate: Vector2i = Vector2i(-1, -1)) -> bool:
	# 如果没有指定坐标，随机生成
	if coordinate == Vector2i(-1, -1):
		coordinate = Vector2i(randi_range(0, board.rows - 1), randi_range(0, board.cols - 1))

	# 检查位置是否可用，如果被占用则重新生成（最多尝试20次）
	if board.has_piece(coordinate):
		var found_empty = false
		for attempt in range(20):  # 增加尝试次数
			coordinate = Vector2i(randi_range(0, board.rows - 1), randi_range(0, board.cols - 1))
			if not board.has_piece(coordinate):
				found_empty = true
				break
		# 如果所有尝试都失败，返回false
		if not found_empty:
			print("错误：无法找到空位置生成棋子")
			return false

	# 找到对应坐标位置的网格
	var cell: Cell = board.get_cell(coordinate)
	var piece: ChessPiece = s_piece.instantiate()
	cell.piece = piece
	piece.piece_type = randi_range(0, PIECE_TYPE_COUNT - 1)

	# 空间压缩机效果：20% 几率生成幽灵球
	if _should_be_ghost(board):
		piece.is_ghost = true
		piece.modulate.a = 0.5  # 幽灵球半透明

	# 生成动画
	piece.scale = Vector2.ZERO
	var tween = board.create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(piece, "scale", Vector2.ONE, 0.3)

	return true

## 检查是否应该生成幽灵球（空间压缩机效果）
## [param board: Board] 棋盘
## [return: bool] 是否生成幽灵球
func _should_be_ghost(board: Board) -> bool:
	# 检查棋盘上是否有空间压缩机
	var placed_items = _get_placed_items(board)

	for item_cell in placed_items:
		if not item_cell.piece or not item_cell.piece.item_data:
			continue

		if item_cell.piece.item_data.id == "space_compressor":
			# 20% 几率生成幽灵球
			if randf() < 0.2:
				return true

	return false

## 获取棋盘上所有已放置的道具
func _get_placed_items(board: Board) -> Array[Cell]:
	var items: Array[Cell] = []
	for i in range(board.rows):
		for j in range(board.cols):
			var cell = board.get_cell(Vector2i(j, i))
			if cell and cell.piece and cell.piece.item_data:
				items.append(cell)
	return items
