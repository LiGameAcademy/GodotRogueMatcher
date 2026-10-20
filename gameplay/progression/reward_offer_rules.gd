class_name RewardOfferRules
extends RefCounted

## 候选失效与系统重建由本局判定，界面不得清组或根据错误文案重抽。
static func prepare(run: RunController, generator: SkillOfferGenerator) -> SkillOffer:
	var rewards: RewardState = run.state.rewards
	var previous: SkillOffer = rewards.active_offer
	if previous != null:
		if previous.choices.is_empty(): return _fail(run, "empty_frozen_offer")
		previous.unavailable.clear()
		for skill: SkillDefinition in previous.choices:
			if skill == null or not skill.validation_error().is_empty(): return _fail(run, "invalid_frozen_skill")
			if not SkillOfferGenerator.CATALOG.any(func(known: SkillDefinition) -> bool: return known.skill_id == skill.skill_id):
				return _fail(run, "unknown_frozen_skill")
			var target: SkillTarget = previous.targets.get(skill.skill_id)
			if target == null: return _fail(run, "missing_frozen_target")
			var target_error: String = _target_error(skill.acquisition_effect(target.level_before), target)
			if not target_error.is_empty(): return _fail(run, target_error)
			var reason: String = SkillRules.rejection(run.state, skill, run.abilities.config)
			if reason.is_empty() and target.level_before != SkillRules.level(run.state, skill): reason = "frozen_skill_level_changed"
			if reason.is_empty(): reason = target_rejection(run.state, skill, target)
			if not reason.is_empty(): previous.unavailable[skill.skill_id] = reason
		if previous.unavailable.size() < previous.choices.size(): return previous
		if rewards.repair_used: return _fail(run, "reward_repair_already_used")
	var offer: SkillOffer = generator.generate(run, previous != null)
	if offer == null: return _fail(run, generator.last_error if not generator.last_error.is_empty() else "offer_generation_failed")
	if previous != null:
		offer.replaces_offer_id = previous.offer_id
		rewards.repair_used = true
	return offer

## 只检查冻结目标及必要前置，不抽样、不执行效果，也不把输入未选色视为失效。
static func target_rejection(state: RunState, skill: SkillDefinition, target: SkillTarget) -> String:
	return _effect_rejection(skill.acquisition_effect(SkillRules.level(state, skill)), target, SkillRules.effect_context(state))

static func _target_error(effect: SkillEffect, target: SkillTarget) -> String:
	if effect == null or target == null: return "invalid_frozen_effect"
	if effect is CompositeEffect:
		var composite: CompositeEffect = effect as CompositeEffect
		var frozen: CompositeSkillTarget = target as CompositeSkillTarget
		if frozen == null or frozen.leaf_targets.size() != composite.children.size(): return "invalid_composite_targets"
		for index: int in range(composite.children.size()):
			var error: String = _target_error(composite.children[index], frozen.leaf_targets[index])
			if not error.is_empty(): return error
	elif not effect is ChoiceEffect:
		return "unsupported_frozen_effect"
	return ""

static func _effect_rejection(effect: SkillEffect, target: SkillTarget, context: ChoiceEffectContext) -> String:
	if effect is CompositeEffect:
		var composite: CompositeEffect = effect as CompositeEffect
		var frozen: CompositeSkillTarget = target as CompositeSkillTarget
		if frozen == null or frozen.leaf_targets.size() != composite.children.size(): return "invalid_composite_targets"
		# 与取得前置一致：后叶须在真正到达时，按其声明及更新后的盘面判断。
		return _effect_rejection(composite.children[0], frozen.leaf_targets[0], context)
	if not effect is ChoiceEffect or target == null: return "invalid_choice_target"
	var choice: ChoiceEffect = effect as ChoiceEffect
	if choice.requires_color_choice():
		if not choice is ClearMaterialEffect: return "invalid_color_selector"
		for color: int in range(target.color_groups.size()):
			var selected: SkillTarget = (choice as ClearMaterialEffect).choose_color(target, color)
			if selected != null and choice.build(context, selected).error.is_empty(): return ""
		return "frozen_colors_unavailable"
	return choice.build(context, target).error

static func _fail(run: RunController, reason: String) -> SkillOffer:
	run.state.rule_error = reason
	run.state.phase = RunState.Phase.ERROR
	return null
