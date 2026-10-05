class_name SkillApplyResult
extends RefCounted

var success: bool = false
var reward_id: int
var offer_id: int
var skill_id: StringName
var error: String = ""
var created: Array[PieceState] = []
var marked_ids: Array[int] = []
var matches: Array[MatchResult] = []
var removed: Array[PieceState] = []
