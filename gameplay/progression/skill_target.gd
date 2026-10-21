class_name SkillTarget
extends RefCounted

var deferred: bool = false

var coordinate: Vector2i = Vector2i(-1, -1)
var piece_ids: Array[int] = []
var cost_piece_ids: Array[int] = []
var color: int = -1
var line_axis: int = -1
var line_index: int = -1
var value_before: int = 0
var value_after: int = 0
var remaining_before: int = 0
var remaining_after: int = 0
var color_groups: Array[PackedInt64Array] = []
var fuse_counts: Array[int] = []
var level_before: int = 0
var level_after: int = 0

func valid_deferred_contract() -> bool:
	return deferred and piece_ids.is_empty() and cost_piece_ids.is_empty() and color == -1 and line_axis == -1 and line_index == -1 and coordinate == Vector2i(-1, -1) and color_groups.is_empty() and fuse_counts.is_empty()

## Color picker / bots read groups here; CompositeSkillTarget redirects to the clear leaf.
func color_picker_source() -> SkillTarget:
	return self

## 界面只拿独立冻结快照，不能改写本局目标。
func copy() -> SkillTarget:
	var result: SkillTarget = SkillTarget.new()
	_copy_into(result)
	return result

func _copy_into(result: SkillTarget) -> void:
	result.deferred = deferred
	result.coordinate = coordinate
	result.piece_ids.assign(piece_ids)
	result.cost_piece_ids.assign(cost_piece_ids)
	result.color = color
	result.line_axis = line_axis
	result.line_index = line_index
	result.value_before = value_before
	result.value_after = value_after
	result.remaining_before = remaining_before
	result.remaining_after = remaining_after
	for group: PackedInt64Array in color_groups: result.color_groups.append(group.duplicate())
	result.fuse_counts.assign(fuse_counts)
	result.level_before = level_before
	result.level_after = level_after
