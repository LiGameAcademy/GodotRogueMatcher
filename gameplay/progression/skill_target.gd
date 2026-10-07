class_name SkillTarget
extends RefCounted

var coordinate: Vector2i = Vector2i(-1, -1)
var piece_ids: Array[int] = []
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
