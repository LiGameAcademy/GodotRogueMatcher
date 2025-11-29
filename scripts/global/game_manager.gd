extends Node

## 游戏管理器（单例）
## 职责：管理游戏状态（分数、棋子数量、游戏结束等）

## 分数
var score: int = 0:
	set(value):
		score = value
		score_changed.emit(value)

## 棋子数量
var piece_count: int = 0:
	set(value):
		piece_count = value
		piece_count_changed.emit(value)

## 最大棋子数量
var max_pieces: int = 81  # 9x9 = 81

## 游戏表单
var game_form: GameForm = null

# 信号
## 分数变化
signal score_changed(new_score: int)
## 棋子数量变化
signal piece_count_changed(new_count: int)
## 游戏结束
signal game_overed

func _ready() -> void:
	reset_game()

## 重置游戏
func reset_game() -> void:
	score = 0
	piece_count = 0

## 增加分数
func add_score(amount: int) -> void:
	score += amount

## 增加棋子数量
func add_piece_count(amount: int) -> void:
	piece_count += amount
	check_game_over()

## 减少棋子数量
func remove_piece_count(amount: int) -> void:
	piece_count -= amount

## 检查游戏是否结束
func check_game_over() -> void:
	if piece_count >= max_pieces - 3:  # 剩余空间不足3个
		game_overed.emit()

## 设置游戏表单（用于UI更新）
func set_game_form(form: GameForm) -> void:
	game_form = form
	if game_form:
		score_changed.connect(game_form.update_score_display)
