class_name RewardState
extends RefCounted

var consumed_count: int = 0
var next_offer_id: int = 1
var active_offer: SkillOffer
var applications: Array[SkillApplyResult] = []
var acquired: Dictionary[StringName, int] = {}
var previous_unselected: Array[StringName] = []
var candidate_random: RandomNumberGenerator = RandomNumberGenerator.new()
var target_random: RandomNumberGenerator = RandomNumberGenerator.new()
var display_random: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(run_seed: int) -> void:
	candidate_random.seed = run_seed ^ 0x1517
	target_random.seed = run_seed ^ 0x2971
	display_random.seed = run_seed ^ 0x3919
