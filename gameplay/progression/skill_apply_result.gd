class_name SkillApplyResult
extends RefCounted

var success: bool = false
var reward_id: int
var offer_id: int
var skill_id: StringName
var error: String = ""
var outcome: StringName = &"rejected"
var target_changes: Array[Dictionary] = []
var completed_leaves: Array[String] = []
var failed_leaf: String = ""
var created: Array[PieceState] = []
var transformed: Array[PieceState] = []
var marked_ids: Array[int] = []
var matches: Array[MatchResult] = []
var removed: Array[PieceState] = []
