class_name ScoreLedger
extends RefCounted

var total: int:
	get:
		return _total
var _total: int = 0
var _next_event_id: int = 1
var _entries: Array[ScoreEntry] = []

static func calculate_base(match_count: int) -> int:
	return match_count * (match_count + 5) if match_count >= 5 else 0

## 每次提交分配事件ID；表现只读取副本，不重新提交。
func commit(match_count: int, multiplier: float = 1.0, extra_score: int = 0, reason: StringName = &"match", root_action_id: int = 0, target_ids: Array[int] = [], source_id: int = 0, ability_id: StringName = &"") -> ScoreEntry:
	if match_count < 0 or multiplier < 0.0 or not is_finite(multiplier) or extra_score < 0:
		return null
	var entry: ScoreEntry = ScoreEntry.new()
	entry.event_id = _next_event_id
	entry.root_action_id = root_action_id
	entry.target_ids = target_ids.duplicate()
	entry.source_id = source_id
	entry.ability_id = ability_id
	entry.reason = reason
	entry.match_count = match_count
	entry.base_score = calculate_base(match_count)
	entry.multiplier = multiplier
	entry.extra_score = extra_score
	entry.final_score = floori(entry.base_score * multiplier + extra_score)
	_next_event_id += 1
	_total += entry.final_score
	_entries.append(entry)
	return entry.copy()

func get_entries() -> Array[ScoreEntry]:
	var result: Array[ScoreEntry] = []
	for entry: ScoreEntry in _entries:
		result.append(entry.copy())
	return result
