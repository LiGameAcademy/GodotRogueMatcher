class_name TelemetryTurn
extends RefCounted

var before: Dictionary
var after: Dictionary
var command_id: String
var root_action_id: String
var created: Dictionary[String, String] = {}
var removed: Dictionary[String, String] = {}
var matched: Dictionary[String, bool] = {}
var blasted: Dictionary[String, bool] = {}
var ledger: Dictionary[String, Dictionary] = {}
var max_generation: int = 0
var rewards_added: int = 0
var _milestone: int
var _choice_score: int = 0
var _choice_occupancy: int = 0

func exclude_choice(row: Dictionary) -> void:
	_choice_score += int(row.after.total) - int(row.before.total)
	_choice_occupancy += row.after.pieces.size() - row.before.pieces.size()

func _init(state: Dictionary, command: String, action: String) -> void:
	before = _summary_state(state)
	after = before
	command_id = command
	root_action_id = action
	_milestone = before.milestone_level.to_int()

func consume(row: Dictionary, skill: Dictionary) -> void:
	after = _summary_state(row.after)
	rewards_added += maxi(0, after.milestone_level.to_int() - _milestone)
	_milestone = after.milestone_level.to_int()
	for data: Dictionary in skill.get("created", []): created[data.id] = data.content_id
	for data: Dictionary in skill.get("removed", []): removed[data.id] = data.content_id
	for data: Dictionary in row.get("removed", []): removed[data.id] = data.content_id
	_events(row.get("events", []))
	for birth: Dictionary in row.get("births", []):
		created[birth.piece.id] = birth.piece.content_id
		_events(birth.events)

func payload(complete: bool) -> Dictionary:
	var added_companions: int = _companions(created)
	var removed_companions: int = _companions(removed)
	return {"turn_id": before.turn.to_int(), "score_before": before.total, "score_after": after.total, "occupied_before": before.pieces.size(), "occupied_after": after.pieces.size(), "created": created.size(), "removed": removed.size(), "created_ordinary": created.size() - added_companions, "created_companions": added_companions, "removed_ordinary": removed.size() - removed_companions, "removed_companions": removed_companions, "match_removed": matched.size(), "blast_removed": blasted.size(), "ledger_entries": ledger.values(), "event_count": ledger.size(), "max_generation": max_generation, "rewards_added": rewards_added, "complete": complete, "action_score_delta": int(after.total) - int(before.total) - _choice_score, "choice_score_excluded": _choice_score, "space_consistent": after.pieces.size() - before.pieces.size() - _choice_occupancy == created.size() - removed.size()}

func _events(events: Array) -> void:
	for event: Dictionary in events:
		max_generation = maxi(max_generation, event.generation.to_int())
		for piece: Dictionary in event.removed:
			removed[piece.id] = piece.content_id
			if event.cause == "match": matched[piece.id] = true
			elif event.cause == "explosion": blasted[piece.id] = true
		var entry: Dictionary = event.score
		if not entry.is_empty():
			var projected: Dictionary = entry.duplicate(true)
			projected["parent_event_id"] = null
			ledger[entry.event_id] = projected

func _companions(pieces: Dictionary[String, String]) -> int:
	var count: int = 0
	for content: String in pieces.values():
		if not content.is_empty(): count += 1
	return count

func _summary_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["turn", "total", "pieces", "milestone_level", "challenge", "spawning", "acquired", "action_refill_count"]:
		result[key] = state[key]
	return result
