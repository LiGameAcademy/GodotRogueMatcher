class_name ScoreEntry
extends RefCounted

var event_id: int = 0
var root_action_id: int = 0
var target_ids: Array[int] = []
var source_id: int = 0
var ability_id: StringName = &""
var reason: StringName = &""
var match_count: int = 0
var base_score: int = 0
var multiplier: float = 1.0
var extra_score: int = 0
var final_score: int = 0

func copy() -> ScoreEntry:
	var result: ScoreEntry = ScoreEntry.new()
	result.event_id = event_id
	result.root_action_id = root_action_id
	result.target_ids = target_ids.duplicate()
	result.source_id = source_id
	result.ability_id = ability_id
	result.reason = reason
	result.match_count = match_count
	result.base_score = base_score
	result.multiplier = multiplier
	result.extra_score = extra_score
	result.final_score = final_score
	return result
