class_name ProgressionState
extends RefCounted

var level: int = 0
var previous_milestone: int = 0
var next_milestone: int

func _init(config: ProgressionConfig) -> void:
	next_milestone = config.threshold(0)

func check_score(state: RunState, config: ProgressionConfig, score_override: int = -1) -> int:
	var gained: int = 0
	var score: int = state.ledger.total if score_override < 0 else score_override
	while score >= next_milestone:
		level += 1
		state.pending_rewards += 1
		gained += 1
		previous_milestone = next_milestone
		next_milestone = config.threshold(level)
	return gained
