class_name StageResult
extends RefCounted

var stage_id: int = 0
var target: int = 0
var target_total: int = 0
var score_total: int = 0
var pressure_interval: int = 0
var base_refill_before_relief: int = 0
var next_base_refill: int = 0
var carry_in: int = 0
var action_score: int = 0
var used_actions: int = 0
var root_action_id: int = 0
var reason: StringName = &""
var carry_out: int = 0
var reward_id: int = 0
var passed_by: StringName = &""
var goal_completed: bool = false
var goal_bonus_score: int = 0
var score_after_goal: int = 0
var goal_score_entry: ScoreEntry

func data() -> Dictionary:
	return {"stage_id": stage_id, "target": target, "target_total": target_total, "score_total": score_total, "pressure_interval": pressure_interval, "base_refill_before_relief": base_refill_before_relief, "next_base_refill": next_base_refill, "carry_in": carry_in, "action_score": action_score, "used_actions": used_actions, "root_action_id": root_action_id, "reason": reason, "carry_out": carry_out, "reward_id": reward_id, "passed_by": passed_by, "goal_completed": goal_completed, "goal_bonus_score": goal_bonus_score, "score_after_goal": score_after_goal, "goal_score": {} if goal_score_entry == null else RunSnapshot.score(goal_score_entry)}
