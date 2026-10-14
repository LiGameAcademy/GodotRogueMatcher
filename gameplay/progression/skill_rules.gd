class_name SkillRules
extends RefCounted

## 技能合法条件和应用入口；与界面、回合动画无关。
static func level(state: RunState, skill: SkillDefinition) -> int:
	if not skill.levels.is_empty():
		var instance: SkillInstance = state.skill_instances.get(skill.skill_id)
		return instance.level if instance != null else 0
	if skill.choice_effect is InstallGoalBonusEffect: return 1 if state.goal_bonus_score > 0 else 0
	if skill.choice_effect is InstallDyeUpgradeEffect:
		return state.dye.level((skill.choice_effect as InstallDyeUpgradeEffect).upgrade)
	if skill.choice_effect is InstallUpgradeEffect:
		return state.explosion.level((skill.choice_effect as InstallUpgradeEffect).upgrade)
	if skill.choice_effect is DemolitionStatEffect:
		return _demolition_stat_level(state, (skill.choice_effect as DemolitionStatEffect).stat)
	return state.rewards.acquired.get(skill.skill_id, 0)

static func unmarked_material(state: RunState) -> Array[int]:
	var ids: Array[int] = []
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id.is_empty() and not state.explosion.instances.has(piece.piece_id):
			ids.append(piece.piece_id)
	return ids

## Shared offer/UI freeze path: acquisition_effect → ChoiceEffect/CompositeEffect.freeze.
static func freeze_target(state: RunState, skill: SkillDefinition, random: RandomNumberGenerator = null) -> SkillTarget:
	var rng: RandomNumberGenerator = random if random != null else state.rewards.target_random
	var effect: SkillEffect = skill.acquisition_effect(level(state, skill))
	var target: SkillTarget = SkillTarget.new()
	if effect is ChoiceEffect:
		target = (effect as ChoiceEffect).freeze(effect_context(state), rng)
	elif effect is CompositeEffect:
		target = (effect as CompositeEffect).freeze(effect_context(state), rng)
	target.level_before = level(state, skill)
	target.level_after = target.level_before + 1
	return target

static func effect_context(state: RunState) -> ChoiceEffectContext:
	var context: ChoiceEffectContext = ChoiceEffectContext.new()
	context.spawn_config = RunController.SPAWN_CONFIG
	context.next_refill = state.next_refill_count()
	context.color_weights = state.spawning.color_weights.duplicate()
	context.refill_batches = state.spawning.refill_batches.duplicate()
	context.upgrades = state.explosion.upgrades.duplicate()
	context.dye_upgrades = state.dye.upgrades.duplicate()
	context.stage_enabled = state.stage.enabled()
	context.goal_bonus_score = state.goal_bonus_score
	context.core_pool_unlocked = state.explosion.core_pool_unlocked
	context.line_row_unlocked = state.line_clear.row_unlocked
	context.line_column_unlocked = state.line_clear.column_unlocked
	context.empty_coordinates = state.rules.state.get_empty_coordinates()
	context.explosion_unlocked = state.explosion.unlocked
	context.radius_level = state.explosion.radius_level
	context.reward_level = state.explosion.reward_level
	context.multiplier_level = state.explosion.multiplier_level
	context.match_extra_level = state.explosion.match_extra_level
	context.blast_extra_level = state.explosion.blast_extra_level
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"special_demolition": context.core_present = true
		if piece.content_id.is_empty(): context.material.append(piece.copy())
		if piece.content_id.is_empty() and state.explosion.instances.has(piece.piece_id): context.fuse_ids.append(piece.piece_id)
	return context

static func rejection(state: RunState, skill: SkillDefinition, config: ExplosionConfig, frozen_pressure: float = -1.0) -> String:
	var definition_error: String = skill.validation_error()
	if not definition_error.is_empty(): return definition_error
	if state.is_game_over or not state.rule_error.is_empty():
		return "本局已经结束或规则异常"
	if not is_finite(skill.base_weight) or skill.base_weight <= 0.0:
		return "技能权重必须为正数"
	if skill.requires_core and not state.explosion.core_pool_unlocked: return "需先获得爆壳手登场"
	if skill.requires_fuse_unlock and not state.explosion.fuse_unlocked: return "需先解锁引信路线"
	if skill.requires_fuse and effect_context(state).fuse_ids.is_empty(): return "棋盘上需要引信"
	if not skill.prerequisite.is_empty() and state.rewards.acquired.get(skill.prerequisite, 0) == 0: return "缺少前置升级"
	var owned: SkillInstance = state.skill_instances.get(skill.skill_id)
	if owned != null and owned.definition != skill: return "技能定义与已安装实例不符"
	if skill.maximum_level > 0 and level(state, skill) >= skill.maximum_level: return "已满级"
	if level(state, skill) >= 1000000: return "等级已达安全上限"
	var early_rescue: bool = RescueOfferRules.early_allowed(state, skill, frozen_pressure)
	if not early_rescue and state.rewards.consumed_count + 1 < skill.minimum_reward: return "尚未进入候选阶段"
	var effect: SkillEffect = skill.acquisition_effect(level(state, skill))
	if effect == null: return "技能缺少执行配置"
	if not early_rescue and state.rewards.consumed_count + 1 < skill.minimum_reward: return "尚未进入中期候选池"
	if not skill.levels.is_empty() and effect is InstallUpgradeEffect:
		var upgrade: StringName = (effect as InstallUpgradeEffect).upgrade
		if state.explosion.level(upgrade) != level(state, skill): return "技能等级与生成修正不一致"
	if not skill.levels.is_empty() and effect is DemolitionStatEffect:
		if _demolition_stat_level(state, (effect as DemolitionStatEffect).stat) != level(state, skill):
			return "技能等级与生成修正不一致"
	if effect is DemolitionStatEffect:
		var capped: String = _demolition_stat_cap(state, config, effect as DemolitionStatEffect)
		if not capped.is_empty(): return capped
	if effect is ChoiceEffect:
		return (effect as ChoiceEffect).rejection(effect_context(state))
	if effect is CompositeEffect:
		return (effect as CompositeEffect).rejection(effect_context(state))
	return "unsupported skill effect"

static func apply(run: RunController, offer_id: int, skill_id: StringName, selected_color: int = -1) -> SkillApplyResult:
	var result: SkillApplyResult = SkillApplyResult.new()
	var state: RunState = run.state
	var rewards: RewardState = state.rewards
	var offer: SkillOffer = rewards.active_offer
	if offer == null or offer.offer_id != offer_id or offer.reward_id != rewards.consumed_count + 1 or state.pending_rewards <= 0 or state.phase != RunState.Phase.REWARDS:
		result.error = "奖励已处理或候选已失效"
		return result
	var skill: SkillDefinition = null
	for choice: SkillDefinition in offer.choices:
		if choice.skill_id == skill_id: skill = choice
	if skill == null:
		result.error = "该技能不在当前候选中"
		return result
	result.error = rejection(state, skill, run.abilities.config)
	if not result.error.is_empty(): return result
	var targets: SkillTarget = offer.targets.get(skill_id)
	if targets == null:
		result.error = "Missing frozen target"
		return result
	var effect: SkillEffect = skill.acquisition_effect(level(state, skill))
	if effect == null:
		result.error = "技能缺少执行配置"
		return result
	result.error = AbilityEffectRunner.preflight(run, effect, targets, selected_color)
	if not result.error.is_empty(): return result
	state.action_id += 1
	state.rule_action_id = state.action_id
	result.error = AbilityEffectRunner.apply_skill_effect(run, effect, targets, result, selected_color)
	if not result.error.is_empty():
		run.abilities.abandon_held_blasts()
		state.rule_error = result.error
		state.phase = RunState.Phase.ERROR
		return result
	result.matches.append_array(DemolitionRules.settle(state, state.rule_action_id))
	if not skill.levels.is_empty():
		var instance: SkillInstance = state.skill_instances.get(skill_id)
		if instance == null:
			instance = SkillInstance.new(skill, offer.reward_id)
			state.skill_instances[skill_id] = instance
		instance.commit_next_level()
	rewards.acquired[skill_id] = rewards.acquired.get(skill_id, 0) + 1
	rewards.previous_unselected.clear()
	for choice: SkillDefinition in offer.choices:
		if choice.skill_id != skill_id: rewards.previous_unselected.append(choice.skill_id)
	rewards.consumed_count += 1
	state.pending_rewards -= 1
	rewards.active_offer = null
	result.success = true
	result.reward_id = offer.reward_id
	result.offer_id = offer_id
	result.skill_id = skill_id
	rewards.applications.append(result)
	return result

static func _demolition_stat_level(state: RunState, stat: DemolitionStatEffect.Stat) -> int:
	match stat:
		DemolitionStatEffect.Stat.RADIUS: return state.explosion.radius_level
		DemolitionStatEffect.Stat.REWARD: return state.explosion.reward_level
		DemolitionStatEffect.Stat.MULTIPLIER: return state.explosion.multiplier_level
		DemolitionStatEffect.Stat.MATCH_EXTRA: return state.explosion.match_extra_level
		DemolitionStatEffect.Stat.BLAST_EXTRA: return state.explosion.blast_extra_level
	return 0

static func _demolition_stat_cap(state: RunState, config: ExplosionConfig, effect: DemolitionStatEffect) -> String:
	match effect.stat:
		DemolitionStatEffect.Stat.RADIUS:
			if state.explosion.radius_level >= config.maximum_radius_level: return "已满级"
		DemolitionStatEffect.Stat.REWARD:
			if state.explosion.reward_level >= config.reward_maximum_level: return "已满级"
	return ""
