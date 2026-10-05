class_name GreedyBot
extends RuleBot

func choose(run: RunController) -> RunCommand:
	version = "greedy-v1"
	if run.state.phase == RunState.Phase.REWARDS:
		if run.state.rewards.active_offer == null: return null
		var best: StringName
		var best_score: float = -INF
		var density: float = float(run.state.rules.state.get_piece_count()) / (run.state.rules.state.columns * run.state.rules.state.rows)
		for skill: SkillDefinition in run.state.rewards.active_offer.choices:
			var value: float = config.skill_weights.get(skill.skill_id, 0.0)
			if not run.state.explosion.unlocked and skill.is_starter: value += config.starter_weight
			if skill.action == SkillDefinition.Action.THIN and density >= config.dense_threshold: value += config.dense_thin_weight
			if value > best_score or (value == best_score and String(skill.skill_id) < String(best)):
				best = skill.skill_id
				best_score = value
		return skill_command(run, best)
	var moves: Array[MovePieceCommand] = legal_moves(run)
	last_legal_count = moves.size()
	if moves.is_empty(): return null
	var colors: Dictionary[Vector2i, int] = {}
	var pieces: Dictionary[int, PieceState] = {}
	for piece: PieceState in run.state.rules.state.get_snapshot():
		colors[piece.coordinate] = piece.match_color
		pieces[piece.piece_id] = piece
	var best: MovePieceCommand = moves[0]
	var best_score: float = -INF
	for move: MovePieceCommand in moves:
		var piece: PieceState = pieces[move.piece_id]
		var score: float = _potential(colors, piece, move.target, run.state.rules.minimum_match_count)
		if score > best_score:
			best_score = score
			best = move
	return best

## 仅评价移走来源后的连续同色线与邻域拥堵，不试算未来随机或连携。
func _potential(colors: Dictionary[Vector2i, int], piece: PieceState, target: Vector2i, match_count: int) -> float:
	var score: float = 0.0
	for direction: Vector2i in BoardRules.MATCH_DIRECTIONS:
		var count: int = 1
		for sign_value: int in [-1, 1]:
			var coordinate: Vector2i = target + direction * sign_value
			while coordinate != piece.coordinate and colors.get(coordinate, -1) == piece.match_color:
				count += 1
				coordinate += direction * sign_value
		score += count * count * config.line_potential_weight
		if count >= match_count: score += config.match_priority
	for direction: Vector2i in BoardRules.MOVE_DIRECTIONS:
		if colors.has(target + direction) and target + direction != piece.coordinate: score -= config.congestion_penalty
	return score
