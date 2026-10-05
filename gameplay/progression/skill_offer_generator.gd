class_name SkillOfferGenerator
extends RefCounted

const CONFIG: OfferConfig = preload("res://gameplay/progression/content/offer_config.tres")

const CATALOG: Array[SkillDefinition] = [
	preload("res://gameplay/progression/content/core_drop.tres"),
	preload("res://gameplay/progression/content/assign_fuse.tres"),
	preload("res://gameplay/progression/content/blast_radius.tres"),
	preload("res://gameplay/progression/content/blast_reward.tres"),
	preload("res://gameplay/progression/content/score_multiplier.tres"),
	preload("res://gameplay/progression/content/match_extra.tres"),
	preload("res://gameplay/progression/content/blast_extra.tres"),
	preload("res://gameplay/progression/content/instant_thin.tres")]

var last_error: String = ""

## 相同待处理奖励返回已冻结候选；重建UI不消耗随机数。
func generate(run: RunController) -> SkillOffer:
	last_error = ""
	var state: RunState = run.state
	if state.pending_rewards <= 0 or state.is_game_over or not state.rule_error.is_empty(): return null
	if state.rewards.active_offer != null: return state.rewards.active_offer
	var rewards: RewardState = state.rewards
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = rewards.next_offer_id
	offer.reward_id = rewards.consumed_count + 1
	offer.rules_version = CONFIG.rules_version
	offer.profile_id = CONFIG.profile_id
	offer.candidate_state_before = rewards.candidate_random.state
	var profile: Dictionary[StringName, float] = build_profile(state)
	var normal: Array[SkillDefinition] = []
	var fallback: Array[SkillDefinition] = []
	for skill: SkillDefinition in CATALOG:
		var reason: String = SkillRules.rejection(state, skill, run.abilities.config)
		if not reason.is_empty():
			offer.pool_log.append("%s: %s" % [skill.skill_id, reason])
			continue
		offer.weights[skill.skill_id] = weight(state, skill, profile)
		if not skill.fallback_only and offer.reward_id >= skill.minimum_reward: normal.append(skill)
		if skill.fallback_only or skill.action in [SkillDefinition.Action.SCORE_MULTIPLIER, SkillDefinition.Action.MATCH_EXTRA, SkillDefinition.Action.BLAST_EXTRA]: fallback.append(skill)
	var used: Array[StringName] = []
	for slot: int in range(3):
		var remaining: Array[SkillDefinition] = _remaining(normal, used)
		var pool: Array[SkillDefinition] = []
		var pool_name: String = "normal"
		if slot == 0 and offer.reward_id <= 2 and not _ever_started(state):
			for skill: SkillDefinition in remaining:
				if skill.is_starter: pool.append(skill)
			if not pool.is_empty(): pool_name = "starter"
		if pool.is_empty() and not remaining.is_empty():
			var split: float = unit_random(rewards.candidate_random)
			offer.pool_log.append("slot=%d split=%.8f" % [slot, split])
			var restricted: bool = split < (CONFIG.explore_probability if slot == 2 else CONFIG.related_probability)
			if restricted:
				pool_name = "explore" if slot == 2 else "related"
				for skill: SkillDefinition in remaining:
					var fits: bool = _explores(skill, profile) if slot == 2 else _related(skill, profile)
					if fits: pool.append(skill)
			if pool.is_empty():
				pool = remaining
				pool_name = "normal"
		if pool.is_empty():
			pool = _remaining(fallback, used)
			pool_name = "fallback"
		if pool.is_empty():
			last_error = "不足三个合法技能，保留奖励"
			return null
		pool.sort_custom(_by_id)
		var sample: float = unit_random(rewards.candidate_random)
		var picked: SkillDefinition = _draw(pool, offer.weights, sample)
		used.append(picked.skill_id)
		offer.choices.append(picked)
		offer.generation_order.append(picked.skill_id)
		offer.pool_log.append("slot=%d pool=%s sample=%.8f selected=%s" % [slot, pool_name, sample, picked.skill_id])
	# 即时目标与显示次序分别使用独立流，避免影响候选和普通生成。
	for skill: SkillDefinition in offer.choices:
		var targets: SkillTarget = SkillTarget.new()
		if skill.action == SkillDefinition.Action.CORE_DROP:
			var empty: Array[Vector2i] = state.rules.state.get_empty_coordinates()
			targets.coordinate = empty[rewards.target_random.randi_range(0, empty.size() - 1)]
		elif skill.action in [SkillDefinition.Action.ASSIGN_FUSE, SkillDefinition.Action.THIN]:
			var ids: Array[int] = SkillRules.unmarked_material(state)
			var count: int = 2 if skill.action == SkillDefinition.Action.ASSIGN_FUSE else skill.target_count
			for index: int in range(mini(count, ids.size())):
				var chosen: int = rewards.target_random.randi_range(0, ids.size() - 1)
				targets.piece_ids.append(ids[chosen])
				ids.remove_at(chosen)
		offer.targets[skill.skill_id] = targets
	for index: int in range(offer.choices.size() - 1, 0, -1):
		var chosen: int = rewards.display_random.randi_range(0, index)
		var temp: SkillDefinition = offer.choices[index]
		offer.choices[index] = offer.choices[chosen]
		offer.choices[chosen] = temp
	offer.candidate_state_after = rewards.candidate_random.state
	rewards.next_offer_id += 1
	rewards.active_offer = offer
	return offer

static func build_profile(state: RunState) -> Dictionary[StringName, float]:
	var profile: Dictionary[StringName, float] = {}
	for skill: SkillDefinition in CATALOG:
		if skill.action == SkillDefinition.Action.THIN: continue
		var current: int = SkillRules.level(state, skill)
		if current <= 0: continue
		var contribution: float = 1.0 + 0.25 * mini(maxi(current - 1, 0), 2)
		for tag: StringName in skill.tags:
			profile[tag] = minf(3.0, profile.get(tag, 0.0) + contribution)
	return profile

static func weight(state: RunState, skill: SkillDefinition, profile: Dictionary[StringName, float]) -> float:
	var affinity: float = 0.0
	for tag: StringName in skill.tags: affinity += profile.get(tag, 0.0)
	if not skill.tags.is_empty(): affinity /= skill.tags.size()
	var factor: float = 1.0 + CONFIG.affinity_gain * affinity
	var driver: bool = not state.explosion.instances.is_empty()
	if skill.need_rule == &"restore_explosion" and profile.get(&"exp", 0.0) >= 1.0 and not driver: factor *= CONFIG.need_factor
	if skill.need_rule == &"explosion_payoff" and driver and state.explosion.reward_level == 0 and state.explosion.blast_extra_level == 0: factor *= CONFIG.need_factor
	if state.rewards.previous_unselected.has(skill.skill_id): factor *= CONFIG.history_factor
	if skill.is_persistent and SkillRules.level(state, skill) > 0: factor *= CONFIG.repeat_factor
	return skill.base_weight * clampf(factor, CONFIG.factor_min, CONFIG.factor_max)

static func unit_random(random: RandomNumberGenerator) -> float:
	return float(random.randi()) / 4294967296.0

func _remaining(pool: Array[SkillDefinition], used: Array[StringName]) -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	for skill: SkillDefinition in pool:
		if not used.has(skill.skill_id): result.append(skill)
	return result

func _ever_started(state: RunState) -> bool:
	return state.explosion.unlocked or state.rewards.acquired.has(&"core_drop") or state.rewards.acquired.has(&"assign_fuse")

func _related(skill: SkillDefinition, profile: Dictionary[StringName, float]) -> bool:
	for tag: StringName in skill.tags:
		if profile.get(tag, 0.0) >= 1.0: return true
	return false

func _explores(skill: SkillDefinition, profile: Dictionary[StringName, float]) -> bool:
	return (skill.tags.has(&"exp") and profile.get(&"exp", 0.0) < 1.0) or not _related(skill, profile)

func _by_id(a: SkillDefinition, b: SkillDefinition) -> bool:
	return String(a.skill_id) < String(b.skill_id)

func _draw(pool: Array[SkillDefinition], weights: Dictionary[StringName, float], sample: float) -> SkillDefinition:
	var total: float = 0.0
	for skill: SkillDefinition in pool: total += weights[skill.skill_id]
	var threshold: float = sample * total
	var cumulative: float = 0.0
	for skill: SkillDefinition in pool:
		cumulative += weights[skill.skill_id]
		if cumulative > threshold: return skill
	return pool.back()
