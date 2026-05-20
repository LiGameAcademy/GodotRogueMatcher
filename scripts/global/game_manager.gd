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

## 当前回合数
var turn_count: int = 0

## 本轮是否产生了得分（用于决定是否生成新棋子）
var score_earned_this_turn: bool = false

# 信号
## 分数变化
signal score_changed(new_score: int)
## 棋子数量变化
signal piece_count_changed(new_count: int)
## 游戏结束
signal game_overed
## 回合开始
signal turn_started(turn_number: int)
## 回合结束
signal turn_ended(turn_number: int)

func _ready() -> void:
	reset_game()

## 重置游戏
func reset_game() -> void:
	score = 0
	piece_count = 0
	turn_count = 0
	score_earned_this_turn = false

## 增加分数
func add_score(amount: int) -> void:
	if amount > 0:
		score_earned_this_turn = true  # 标记本轮产生了得分
	score += amount
	# 检查是否触发升级
	# 注意：LevelUpSystem 是 Autoload 单例，运行时可用
	# 使用 get_node 获取单例引用（静态分析可能无法识别 Autoload）
	var level_up_system = get_node_or_null("/root/LevelUpSystem")
	if level_up_system:
		level_up_system.check_level_up(score)

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

## 开始新回合
func start_turn() -> void:
	turn_count += 1
	score_earned_this_turn = false  # 重置得分标志
	turn_started.emit(turn_count)
	print("回合开始：", turn_count)

## 结束当前回合
func end_turn() -> void:
	turn_ended.emit(turn_count)
	print("回合结束：", turn_count)
