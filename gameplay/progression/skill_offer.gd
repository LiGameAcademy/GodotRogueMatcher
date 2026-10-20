class_name SkillOffer
extends RefCounted

var offer_id: int
var reward_id: int
var choices: Array[SkillDefinition] = []
var generation_order: Array[StringName] = []
var targets: Dictionary[StringName, SkillTarget] = {}
var rules_version: String = "offer-v0.1"
var profile_id: StringName = &"prototype_explosion"
var baseline_weights: Dictionary[StringName, float] = {}
var weights: Dictionary[StringName, float] = {}
var pressure_snapshot: Dictionary = {}
var rescue_multiplier: float = 1.0
var pool_log: Array[String] = []
var candidate_state_before: int
var candidate_state_after: int
var unavailable: Dictionary[StringName, String] = {}
var replaces_offer_id: int = 0

func snapshot() -> SkillOffer:
	var result: SkillOffer = SkillOffer.new()
	result.offer_id = offer_id
	result.reward_id = reward_id
	result.choices.assign(choices)
	result.generation_order.assign(generation_order)
	for id: StringName in targets: result.targets[id] = targets[id].copy()
	result.rules_version = rules_version
	result.profile_id = profile_id
	result.baseline_weights.assign(baseline_weights)
	result.weights.assign(weights)
	result.pressure_snapshot = pressure_snapshot.duplicate(true)
	result.rescue_multiplier = rescue_multiplier
	result.pool_log.assign(pool_log)
	result.candidate_state_before = candidate_state_before
	result.candidate_state_after = candidate_state_after
	result.unavailable.assign(unavailable)
	result.replaces_offer_id = replaces_offer_id
	return result
