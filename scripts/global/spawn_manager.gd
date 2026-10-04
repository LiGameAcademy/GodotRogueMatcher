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
	var spawned_count: int = 0
	for i: int in range(SPAWN_COUNT):
		var empty_cells: Array[Cell] = board.get_empty_cells()
		if empty_cells.is_empty():
			GameManager.finish_game()
			return spawned_count
		var cell: Cell = empty_cells.pick_random()
		if not spawn_piece(board, cell.coordinate):
			push_error("合法空位生成失败")
			return spawned_count
		spawned_count += 1
		await MatchSystem.check_and_eliminate(board, cell)
	if board.get_empty_cells().is_empty():
		GameManager.finish_game()

	print("生成棋子完成：成功 ", spawned_count, "/", SPAWN_COUNT)
	return spawned_count

## 在指定位置生成一个随机的棋子
## [param board: Board] 棋盘
## [param coordinate: Vector2i] 指定坐标
## [return] 是否成功生成
func spawn_piece(board: Board, coordinate: Vector2i = Vector2i(-1, -1)) -> bool:
	# 如果没有指定坐标，随机生成
	if coordinate == Vector2i(-1, -1):
		var empty_cells: Array[Cell] = board.get_empty_cells()
		if empty_cells.is_empty():
			return false
		coordinate = empty_cells.pick_random().coordinate

	# 空位与边界只查询权威规则状态。
	if not board.rules.state.is_valid_coordinate(coordinate) or board.has_piece(coordinate):
		return false

	# 找到对应坐标位置的网格
	var piece: ChessPiece = s_piece.instantiate()
	piece.piece_type = randi_range(0, PIECE_TYPE_COUNT - 1)

	# 空间压缩机效果：20% 几率生成幽灵球
	if _should_be_ghost(board):
		piece.is_ghost = true
		piece.modulate.a = 0.5  # 幽灵球半透明
	if not board.place_piece(coordinate, piece):
		piece.free()
		return false

	# 生成动画
	piece.scale = Vector2.ZERO
	var tween: Tween = board.create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(piece, "scale", Vector2.ONE, 0.3)

	return true

## 检查是否应该生成幽灵球（空间压缩机效果）
## [param board: Board] 棋盘
## [return: bool] 是否生成幽灵球
func _should_be_ghost(board: Board) -> bool:
	# 检查棋盘上是否有空间压缩机
	for snapshot: PieceState in board.rules.state.get_snapshot():
		if snapshot.content_id == &"space_compressor":
			# 20% 几率生成幽灵球
			if randf() < 0.2:
				return true

	return false
