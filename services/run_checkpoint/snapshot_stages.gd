extends RefCounted

## Cold stage restoration. Historical stages are reduced to the last continuation obligation.
const V: Script = preload("res://services/run_checkpoint/snapshot_values.gd")

static func restore(run: RunController, value: Dictionary) -> bool:
	var stage: StageState = run.state.stage
	if not value.get("enabled") is bool or value.enabled != stage.enabled(): return false
	if not V.scalars(stage, value, {"continuing": "continuing", "index": "index", "carry_in": "carry_in", "action_score": "action_score", "used_actions": "used_actions", "awaiting_reward": "awaiting_reward", "root_action_id": "root_action_id", "settled_root_id": "settled_root_id", "entry_offset": "entry_offset"}): return false
	if stage.index < 0 or stage.index > 1000000 or stage.carry_in < 0 or stage.action_score < 0 or stage.used_actions < 0 or stage.entry_offset != 0: return false
	if stage.root_action_id < 0 or stage.settled_root_id < 0 or stage.settled_root_id > stage.root_action_id or stage.root_action_id > run.state.action_id: return false
	if not value.get("history") is Array or value.history.size() > 1: return false
	if not stage.enabled(): return value.history.is_empty()
	if not stage.continuing and stage.index >= stage.config.targets.size(): return false
	var base: int = 0
	for target: int in stage.config.targets: base += target
	var extra: int = maxi(0, stage.index + 1 - stage.config.targets.size())
	@warning_ignore("integer_division")
	var maximum_extra: int = (9223372036854775807 - base) / stage.config.targets.back()
	if extra > maximum_extra: return false
	if stage.awaiting_reward and (run.state.phase != RunState.Phase.REWARDS or run.state.pending_rewards != 1): return false
	if stage.root_action_id != stage.settled_root_id and run.continuation not in [&"before_end", &"after_end"]: return false
	for item: Variant in value.history:
		if not item is Dictionary: return false
		var result: StageResult = StageResult.new()
		if not V.scalars(result, item, {"stage_id": "stage_id", "target": "target", "target_total": "target_total", "score_total": "score_total", "pressure_interval": "pressure_interval", "base_refill_before_relief": "base_refill_before_relief", "next_base_refill": "next_base_refill", "carry_in": "carry_in", "action_score": "action_score", "used_actions": "used_actions", "root_action_id": "root_action_id", "reason": "reason", "carry_out": "carry_out", "reward_id": "reward_id", "passed_by": "passed_by", "goal_completed": "goal_completed", "goal_bonus_score": "goal_bonus_score", "score_after_goal": "score_after_goal"}): return false
		if result.stage_id not in [stage.index, stage.index + 1] or result.reason not in [&"stage_passed", &"challenge_completed"]: return false
		if result.score_total < 0 or result.score_total > run.state.ledger.total or result.target <= 0 or result.used_actions < 1: return false
		if not item.get("goal_score") is Dictionary: return false
		if not item.goal_score.is_empty():
			result.goal_score_entry = _score(item.goal_score)
			if result.goal_score_entry == null: return false
		stage.history.append(result)
	if stage.awaiting_reward:
		if stage.history.is_empty() or stage.history.back().stage_id != stage.index + 1: return false
		if stage.history.back().reason == &"challenge_completed" and not stage.continuing: return false
	return true

static func _score(value: Dictionary) -> ScoreEntry:
	var score: ScoreEntry = ScoreEntry.new()
	if not V.scalars(score, value, {"event_id": "event_id", "action_id": "root_action_id", "source_id": "source_id", "ability_id": "ability_id", "reason": "reason", "N": "match_count", "B": "base_score", "E": "extra_score", "final_score": "final_score"}): return null
	if not value.get("G") is float or not is_finite(value.G) or value.G < 0.0 or not V.ints(value.get("targets"), 1): return null
	score.multiplier = value.G
	for id: String in value.targets: score.target_ids.append(id.to_int())
	if JSON.stringify(RunSnapshot.score(score), "", true, true) != JSON.stringify(value, "", true, true): return null
	return score
