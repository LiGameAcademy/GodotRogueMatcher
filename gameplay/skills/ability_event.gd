class_name AbilityEvent
extends RefCounted

## In-run rule event; source is a removal snapshot and plugins only read value fields.
const PIECE_ELIMINATED: StringName = &"piece_eliminated"

var event_type: StringName = PIECE_ELIMINATED
var event_id: int = 0
var run_id: String = ""
var parent_event_id: int = 0
var source_ability_id: StringName = &""
## Non-serialized run identity; events from a previous retry cannot enter a new dispatcher.
var scope: RefCounted
var cause: StringName = &""
var source: PieceState
var root_action_id: int = 0
var generation: int = 0

## Export a read-only context dictionary for condition queries.
func to_context() -> Dictionary:
	return {"event_id": event_id, "run_id": run_id, "parent_event_id": parent_event_id,
		"source_ability_id": source_ability_id, "event_type": event_type, "cause": cause, "source_id": source.piece_id,
		"match_color": source.match_color, "content_id": source.content_id,
		"coordinate": source.coordinate, "root_action_id": root_action_id, "generation": generation}
