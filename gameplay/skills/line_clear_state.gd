class_name LineClearState
extends RefCounted

const AXIS_ROW: int = 0
const AXIS_COLUMN: int = 1
const CONTENT_ROW: StringName = &"special_line_row"
const CONTENT_COLUMN: StringName = &"special_line_column"

var row_unlocked: bool = false
var column_unlocked: bool = false
var instances: Dictionary[int, AbilityInstance] = {}
var upgrades: Dictionary[StringName, int] = {}

func level(upgrade: StringName) -> int:
	return upgrades.get(upgrade, 0)

func unlocked(axis: int) -> bool:
	return row_unlocked if axis == AXIS_ROW else column_unlocked

func content_id(axis: int) -> StringName:
	return CONTENT_ROW if axis == AXIS_ROW else CONTENT_COLUMN

static func axis_of(content_id: StringName) -> int:
	if content_id == CONTENT_ROW: return AXIS_ROW
	if content_id == CONTENT_COLUMN: return AXIS_COLUMN
	return -1

static func is_line_piece(content_id: StringName) -> bool:
	return axis_of(content_id) >= 0
