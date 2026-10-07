class_name AbilityEvent
extends RefCounted

## 局内规则事件；来源为离场快照，插件只获得值字段。
const PIECE_ELIMINATED: StringName = &"piece_eliminated"

var event_type: StringName = PIECE_ELIMINATED
var cause: StringName = &""
var source: PieceState
var root_action_id: int = 0
var generation: int = 0

func to_context() -> Dictionary:
	return {"event_type": event_type, "cause": cause, "source_id": source.piece_id,
		"match_color": source.match_color, "content_id": source.content_id,
		"coordinate": source.coordinate, "root_action_id": root_action_id, "generation": generation}
