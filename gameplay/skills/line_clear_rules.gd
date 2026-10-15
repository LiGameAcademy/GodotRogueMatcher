class_name LineClearRules
extends RefCounted

const CONFIG: LineClearConfig = preload("res://gameplay/skills/content/line_clear_config.tres")

static func score_per_target(level: int) -> int:
	return maxi(0, level) * CONFIG.score_per_target_per_level

static func score_bonus(state: LineClearState, removed_count: int) -> int:
	return maxi(0, removed_count) * score_per_target(state.level(&"line_clear_score"))

static func upgrade_for_axis(axis: int) -> StringName:
	if axis == LineClearState.AXIS_ROW: return &"line_row_span"
	if axis == LineClearState.AXIS_COLUMN: return &"line_column_span"
	return &""

static func radius(state: LineClearState, axis: int) -> int:
	return maxi(0, state.level(upgrade_for_axis(axis))) * CONFIG.span_radius_per_level

static func line_count(level: int) -> int:
	return 1 + 2 * maxi(0, level) * CONFIG.span_radius_per_level

static func cross_radius(state: LineClearState, axis: int) -> int:
	return radius(state, 1 - axis) if state.level(&"line_cross_upgrade") > 0 else -1
