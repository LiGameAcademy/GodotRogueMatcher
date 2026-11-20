class_name RewardState
extends RefCounted

var consumed_count: int = 0
var next_offer_id: int = 1
var repair_used: bool = false
var active_offer: SkillOffer
var applications: Array[SkillApplyResult] = []
var acquired: Dictionary[StringName, int] = {}
var previous_unselected: Array[StringName] = []
## References to the run-owned offer streams; generation commits temporary states atomically.
var candidate_random: RandomNumberGenerator
var target_random: RandomNumberGenerator
var display_random: RandomNumberGenerator

func _init(run_seed: int, streams: RunRandomStreams = null) -> void:
	candidate_random = streams.stream(&"offer_candidates") if streams != null else RunRandomStreams.create(run_seed, &"offer_candidates")
	target_random = streams.stream(&"offer_targets") if streams != null else RunRandomStreams.create(run_seed, &"offer_targets")
	display_random = streams.stream(&"offer_order") if streams != null else RunRandomStreams.create(run_seed, &"offer_order")
