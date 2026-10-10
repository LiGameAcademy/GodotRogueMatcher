class_name RunStepResult
extends RefCounted

var matches: Array[MatchResult] = []

var kind: StringName
var spawns: Array[SpawnResult] = []
var offer: SkillOffer

var challenge: StageResult
var goal_before: Dictionary = {}
