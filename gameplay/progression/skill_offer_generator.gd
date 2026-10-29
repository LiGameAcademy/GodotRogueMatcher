class_name SkillOfferGenerator
extends RefCounted

const CONFIG: OfferConfig = preload("res://gameplay/progression/content/offer_config.tres")

const CATALOG: Array[SkillDefinition] = [
	preload("res://gameplay/progression/content/instant_core_transform.tres"),
	preload("res://gameplay/progression/content/instant_row_transform.tres"),
	preload("res://gameplay/progression/content/instant_column_transform.tres"),
	preload("res://gameplay/progression/content/composite_refill_color.tres"),
	preload("res://gameplay/progression/content/composite_clear_dye.tres"),
	preload("res://gameplay/progression/content/goal_score_bonus.tres"),
	preload("res://gameplay/progression/content/line_row_drop.tres"),
	preload("res://gameplay/progression/content/line_column_drop.tres"),
	preload("res://gameplay/progression/content/line_manual_clear.tres"),
	preload("res://gameplay/progression/content/line_row_span.tres"),
	preload("res://gameplay/progression/content/line_column_span.tres"),
	preload("res://gameplay/progression/content/line_cross_upgrade.tres"),
	preload("res://gameplay/progression/content/line_clear_score.tres"),
	preload("res://gameplay/progression/content/core_drop.tres"),
	preload("res://gameplay/progression/content/assign_fuse.tres"),
	preload("res://gameplay/progression/content/blast_extra.tres"),
	preload("res://gameplay/progression/content/score_multiplier.tres"),
	preload("res://gameplay/progression/content/match_extra.tres"),
	preload("res://gameplay/progression/content/instant_thin.tres"),
	preload("res://gameplay/progression/content/instant_percent_clear.tres"),
	preload("res://gameplay/progression/content/refill_less.tres"),
	preload("res://gameplay/progression/content/refill_more.tres"),
	preload("res://gameplay/progression/content/precision_reward.tres"),
	preload("res://gameplay/progression/content/fuse_capacity.tres"),
	preload("res://gameplay/progression/content/blast_radius.tres"),
	preload("res://gameplay/progression/content/blast_reward.tres"),
	preload("res://gameplay/progression/content/color_weight_up.tres"),
	preload("res://gameplay/progression/content/color_weight_down.tres"),
	preload("res://gameplay/progression/content/relay_capacity.tres"),
	preload("res://gameplay/progression/content/marked_reward.tres"),
	preload("res://gameplay/progression/content/longline_reward.tres"),
	preload("res://gameplay/progression/content/core_supply_up.tres"),
	preload("res://gameplay/progression/content/core_radius.tres"),
	preload("res://gameplay/progression/content/instant_color_clear.tres"),
	preload("res://gameplay/progression/content/instant_line_clear.tres"),
	preload("res://gameplay/progression/content/fuse_relay.tres"),
	preload("res://gameplay/progression/content/chain_reward.tres"),
	preload("res://gameplay/progression/content/instant_fuse_ignite.tres"),
	preload("res://gameplay/progression/content/core_manual_detonation.tres"),
	preload("res://gameplay/progression/content/fuse_match_plant.tres"),
	preload("res://gameplay/progression/content/blast_chain_bonus.tres"),
	preload("res://gameplay/progression/content/selective_blast.tres"),
	preload("res://gameplay/progression/content/core_fuse_payload.tres"),
	preload("res://gameplay/progression/content/blast_chain_radius.tres"),
	preload("res://gameplay/progression/content/blast_refill_relief.tres"),
	preload("res://gameplay/progression/content/blast_aftershock.tres"),
	preload("res://gameplay/progression/content/match_dye_echo.tres"),
	preload("res://gameplay/progression/content/dye_target_up.tres"),
	preload("res://gameplay/progression/content/dye_chain_depth.tres"),
	preload("res://gameplay/progression/content/dye_mark_reward.tres"),
	preload("res://gameplay/progression/content/blast_dye.tres"),
	preload("res://gameplay/progression/content/instant_color_dye.tres")]

## One legal pool, weighted without replacement. Only complete groups commit three offer streams.
var last_error: String = ""
var config: OfferConfig = CONFIG
var _catalog: Array[SkillDefinition] = []

func _init() -> void:
	_catalog.assign(CATALOG)

func set_catalog(catalog: Array[SkillDefinition]) -> void:
	_catalog.assign(catalog)

func catalog() -> Array[SkillDefinition]:
	return _catalog.duplicate()

func generate(run: RunController, replacing: bool = false) -> SkillOffer:
	last_error = ""
	var state: RunState = run.state
	if state.pending_rewards <= 0 or state.is_game_over or not state.rule_error.is_empty(): return null
	if state.rewards.active_offer != null and not replacing: return state.rewards.active_offer
	last_error = config.validation_error() if config != null else "missing_offer_config"
	if not last_error.is_empty(): return null
	var definitions: Array[SkillDefinition] = CATALOG.duplicate()
	definitions.append_array(_catalog)
	var build: SkillBuildSnapshot = SkillBuildSnapshot.capture(state, definitions)
	var rewards: RewardState = state.rewards
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = rewards.next_offer_id
	offer.reward_id = rewards.consumed_count + 1
	offer.rules_version = config.rules_version
	offer.profile_id = config.profile_id
	offer.build_snapshot = build.data()
	offer.parameter_snapshot = config.data()
	offer.pressure_snapshot = BoardPressure.evaluate(state.rules.state.columns, state.rules.state.rows, _coordinates(state), config.occupancy_weight)
	offer.candidate_state_before = rewards.candidate_random.state
	var legal: Array[SkillDefinition] = []
	var ids: Array[StringName] = []
	for skill: SkillDefinition in _catalog:
		if skill == null or skill.skill_id.is_empty() or ids.has(skill.skill_id):
			last_error = "null_or_duplicate_skill_definition"
			return null
		ids.append(skill.skill_id)
		last_error = skill.validation_error()
		if not last_error.is_empty(): return null
		var reason: String = SkillRules.rejection(state, skill, run.abilities.config, -1.0, build)
		var explanation: Dictionary = OfferWeightRules.evaluate(skill, build, offer.reward_id, reason, config)
		explanation["level_before"] = SkillRules.level(state, skill)
		explanation["acquired_count"] = rewards.acquired.get(skill.skill_id, 0)
		explanation["minimum_reward"] = skill.minimum_reward
		explanation["maximum_level"] = skill.maximum_level
		explanation["prerequisite"] = skill.prerequisite
		offer.explanations[skill.skill_id] = explanation
		offer.weights[skill.skill_id] = explanation.W
		offer.baseline_weights[skill.skill_id] = explanation.H * explanation.B * explanation.Q
		if not reason.is_empty():
			offer.pool_log.append("%s: %s" % [skill.skill_id, reason])
			continue
		if not is_finite(float(explanation.W)) or float(explanation.W) <= 0.0:
			last_error = "invalid_legal_weight"
			return null
		legal.append(skill)
	legal.sort_custom(_by_id)
	var candidate_random: RandomNumberGenerator = _copy_random(rewards.candidate_random)
	var target_random: RandomNumberGenerator = _copy_random(rewards.target_random)
	var display_random: RandomNumberGenerator = _copy_random(rewards.display_random)
	var utility_count: int = 0
	for slot: int in range(3):
		var remaining: Array[SkillDefinition] = []
		var remaining_weights: Dictionary[StringName, float] = {}
		var quota_excluded: Array[StringName] = []
		var denominator: float = 0.0
		for skill: SkillDefinition in legal:
			if offer.generation_order.has(skill.skill_id): continue
			if skill.counts_as_utility_pick() and config.maximum_utility_picks >= 0 and utility_count >= config.maximum_utility_picks:
				quota_excluded.append(skill.skill_id)
				continue
			remaining.append(skill)
			remaining_weights[skill.skill_id] = offer.weights[skill.skill_id]
			denominator += offer.weights[skill.skill_id]
		if remaining.is_empty():
			offer.slot_log.append({"slot": slot, "weights": remaining_weights, "denominator": 0.0,
				"sample": null, "sampled": false, "selected": null, "quota_excluded": quota_excluded})
			break
		if not is_finite(denominator) or denominator <= 0.0:
			last_error = "invalid_slot_denominator"
			return null
		var sample: float = unit_random(candidate_random) if remaining.size() > 1 else 0.0
		var picked: SkillDefinition = _draw(remaining, remaining_weights, denominator, sample)
		offer.choices.append(picked)
		offer.generation_order.append(picked.skill_id)
		if picked.counts_as_utility_pick(): utility_count += 1
		offer.slot_log.append({"slot": slot, "weights": remaining_weights, "denominator": denominator,
			"sample": sample, "sampled": remaining.size() > 1, "selected": picked.skill_id, "quota_excluded": quota_excluded})
	if offer.choices.is_empty():
		last_error = "no_legal_candidates"
		return null
	for skill: SkillDefinition in offer.choices:
		var target: SkillTarget = SkillRules.freeze_target(state, skill, target_random)
		last_error = RewardOfferRules.target_rejection(state, skill, target)
		if not last_error.is_empty(): return null
		offer.targets[skill.skill_id] = target
	for index: int in range(offer.choices.size() - 1, 0, -1):
		var chosen: int = display_random.randi_range(0, index)
		var temp: SkillDefinition = offer.choices[index]
		offer.choices[index] = offer.choices[chosen]
		offer.choices[chosen] = temp
	offer.candidate_state_after = candidate_random.state
	rewards.candidate_random.state = candidate_random.state
	rewards.target_random.state = target_random.state
	rewards.display_random.state = display_random.state
	rewards.next_offer_id += 1
	rewards.active_offer = offer
	return offer

static func build_snapshot(state: RunState) -> SkillBuildSnapshot:
	return SkillBuildSnapshot.capture(state, CATALOG)

static func weight(state: RunState, skill: SkillDefinition, build: SkillBuildSnapshot = null) -> float:
	var frozen: SkillBuildSnapshot = build if build != null else build_snapshot(state)
	var reason: String = SkillRules.rejection(state, skill, AbilityResolver.DEFAULT_CONFIG, -1.0, frozen)
	return float(OfferWeightRules.evaluate(skill, frozen, state.rewards.consumed_count + 1, reason, CONFIG).W)

static func version_for_mode(_mode_id: StringName) -> String:
	return CONFIG.rules_version

static func unit_random(random: RandomNumberGenerator) -> float:
	return float(random.randi()) / 4294967296.0

static func _copy_random(source: RandomNumberGenerator) -> RandomNumberGenerator:
	var result: RandomNumberGenerator = RandomNumberGenerator.new()
	result.seed = source.seed
	result.state = source.state
	return result

static func _coordinates(state: RunState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for piece: PieceState in state.rules.state.get_snapshot(): result.append(piece.coordinate)
	return result

static func _by_id(a: SkillDefinition, b: SkillDefinition) -> bool:
	return String(a.skill_id) < String(b.skill_id)

static func _draw(pool: Array[SkillDefinition], weights: Dictionary[StringName, float], total: float, sample: float) -> SkillDefinition:
	var cumulative: float = 0.0
	for skill: SkillDefinition in pool:
		cumulative += weights[skill.skill_id]
		if cumulative > sample * total: return skill
	return pool.back()
