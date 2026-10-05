extends Node

## 旧HUD/道具兼容桥；局内状态与总分由显式绑定的RunController拥有。
var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 0)
var ledger: ScoreLedger:
	get:
		return run.state.ledger
var score: int:
	get:
		return ledger.total
var turn_count: int:
	get:
		return run.state.turn_count
var is_game_over: bool:
	get:
		return run.state.is_game_over
var piece_count: int = 0:
	set(value):
		piece_count = value
		piece_count_changed.emit(value)
var _game_over_notified: bool = false

signal score_changed(new_score: int)
signal piece_count_changed(new_count: int)
signal game_overed
signal turn_started(turn_number: int)
signal turn_ended(turn_number: int)

func _ready() -> void:
	reset_game()

func reset_game(controller: RunController = null) -> void:
	if controller != null:
		run = controller
	else:
		run.state.reset_counters()
	_game_over_notified = false
	score_changed.emit(0)
	piece_count = 0

func add_score(amount: int) -> void:
	if amount <= 0:
		return
	ledger.commit(0, 1.0, amount, &"legacy_extra", run.state.action_id)
	publish_score()

## 广播已提交总分并排队奖励；表现播放不重复提交账本。
func publish_score() -> void:
	score_changed.emit(score)
	run.check_rewards()

func finish_game() -> void:
	if _game_over_notified or not run.state.rule_error.is_empty():
		return
	run.finish_game()
	_game_over_notified = true
	game_overed.emit()

func start_turn() -> void:
	if is_game_over or not run.state.rule_error.is_empty():
		return
	run.start_turn()
	turn_started.emit(turn_count)

func end_turn() -> void:
	if not run.state.rule_error.is_empty():
		return
	run.end_turn()
	turn_ended.emit(turn_count)
