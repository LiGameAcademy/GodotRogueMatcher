class_name RuleBot
extends RefCounted

var random: RandomNumberGenerator = RandomNumberGenerator.new()
var version: String = "random-legal-v1"
var config: BotConfig = preload("res://tools/bot_testing/bot_config.tres")
var last_legal_count: int = 0

func _init(seed_value: int = 1) -> void:
	random.seed = seed_value

func choose(run: RunController) -> RunCommand:
	if run.state.phase == RunState.Phase.REWARDS:
		var offer: SkillOffer = run.state.rewards.active_offer
		if offer == null: return null
		var index: int = random.randi_range(0, offer.choices.size() - 1)
		return skill_command(run, offer.choices[index].skill_id)
	var moves: Array[MovePieceCommand] = legal_moves(run)
	last_legal_count = moves.size()
	if moves.is_empty(): return null
	return moves[random.randi_range(0, moves.size() - 1)]

func skill_command(run: RunController, id: StringName) -> ChooseSkillCommand:
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = run.state.rewards.active_offer.offer_id
	command.reward_id = run.state.rewards.active_offer.reward_id
	command.skill_id = id
	command.source = "bot"
	return command

## 每枚棋子一次四邻域洪泛，枚举全部合法配对后等概率抽选。
func legal_moves(run: RunController) -> Array[MovePieceCommand]:
	var result: Array[MovePieceCommand] = []
	var board: BoardState = run.state.rules.state
	for piece: PieceState in board.get_snapshot():
		var queue: Array[Vector2i] = [piece.coordinate]
		var visited: Dictionary[Vector2i, bool] = {piece.coordinate: true}
		var cursor: int = 0
		var targets: Array[Vector2i] = []
		while cursor < queue.size():
			var coordinate: Vector2i = queue[cursor]
			cursor += 1
			for direction: Vector2i in BoardRules.MOVE_DIRECTIONS:
				var next: Vector2i = coordinate + direction
				if visited.has(next) or not board.is_valid_coordinate(next) or board.get_piece_id(next) != 0: continue
				visited[next] = true
				queue.append(next)
				targets.append(next)
		targets.sort_custom(_coordinate_order)
		for target: Vector2i in targets:
			var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
			command.piece_id = piece.piece_id
			command.target = target
			command.source = "bot"
			result.append(command)
	return result

func _coordinate_order(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
