class_name StageResult
extends RefCounted

var stage_id: int = 0
var target: int = 0
var action_limit: int = 0
var carry_in: int = 0
var action_score: int = 0
var used_actions: int = 0
var root_action_id: int = 0
var reason: StringName = &""
var carry_out: int = 0
var reward_id: int = 0
var passed_by: StringName = &""

func data() -> Dictionary:
	return {"stage_id": stage_id, "target": target, "action_limit": action_limit, "carry_in": carry_in, "action_score": action_score, "used_actions": used_actions, "root_action_id": root_action_id, "reason": reason, "carry_out": carry_out, "reward_id": reward_id, "passed_by": passed_by}
