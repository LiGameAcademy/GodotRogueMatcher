extends Node

## 生成管理器（单例）
## 职责：管理棋子的生成逻辑

## 每次生成的棋子数量
const SPAWN_COUNT: int = 3

## 棋子类型数量
const PIECE_TYPE_COUNT: int = 5

## 棋子预制体
var s_piece: PackedScene = preload("res://gameplay/board/piece/chess_piece.tscn")

## 生成随机棋子
## [param board: Board] 棋盘
## [return] 成功生成的棋子数量
func spawn_random_pieces(board: Board) -> int:
	var spawned_count: int = 0
	var active_run: RunController = board.run
	for index: int in range(board.run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)):
		var result: SpawnResult = board.run.spawn_one()
		if result == null:
			if board.run.state.rule_error.is_empty():
				GameManager.finish_game()
			return spawned_count
		spawned_count += 1
		await board.present_spawns([result])
		if board.run != active_run or not board.director.error.is_empty():
			return spawned_count
		GameManager.piece_count = board.rules.state.get_piece_count()
		if not board.run.state.rule_error.is_empty():
			board.can_selected = false
			return spawned_count
	board.run.check_space_after_spawning()
	if board.run.state.is_game_over:
		GameManager.finish_game()
	return spawned_count

