class_name SkillOffer
extends RefCounted

var offer_id: int
var reward_id: int
var choices: Array[SkillDefinition] = []
var generation_order: Array[StringName] = []
var targets: Dictionary[StringName, SkillTarget] = {}
var rules_version: String = "offer-v0.1"
var profile_id: StringName = &"prototype_explosion"
var weights: Dictionary[StringName, float] = {}
var pool_log: Array[String] = []
var candidate_state_before: int
var candidate_state_after: int
