class_name GoalCompletionRules
extends RefCounted

## 只接收完整行动达标后的唯一凭证；不重新判关，也不触碰随机流。
static func resolve(state: RunState, result: StageResult) -> void:
	if result.goal_completed or result.reason not in [&"stage_passed", &"challenge_completed"]: return
	result.goal_completed = true
	# 当前选卡尚未发生；此值就是达标时已安装能力的快照。
	result.goal_bonus_score = state.goal_bonus_score
	if result.goal_bonus_score > 0:
		result.goal_score_entry = state.ledger.commit(0, 1.0, result.goal_bonus_score, &"goal_score_bonus", 0, [], 0, &"goal_score_bonus")
	result.score_after_goal = state.ledger.total
	if result.reason == &"stage_passed":
		result.carry_out = maxi(0, state.ledger.total - result.target_total)
	else:
		result.carry_out = 0
