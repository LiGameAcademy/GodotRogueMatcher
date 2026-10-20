extends GutTest

func _run(run_seed: int = 7) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), run_seed)

func _offer(run: RunController, skill: SkillDefinition) -> SkillOffer:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	return offer

func test_catalog_refill_color_matches_displayed_frozen_color() -> void:
	var mismatches: int = 0
	var skill: SkillDefinition = preload("res://gameplay/progression/content/composite_refill_color.tres")
	for run_seed: int in range(10):
		var run: RunController = _run(run_seed)
		var offer: SkillOffer = _offer(run, skill)
		var frozen: CompositeSkillTarget = offer.targets[skill.skill_id] as CompositeSkillTarget
		var preview_color: int = frozen.leaf_targets[1].color
		var before: Array[int] = run.state.spawning.color_weights.duplicate()
		var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
		assert_true(result.success, result.error)
		var actual_color: int = -1
		for color: int in range(before.size()):
			if run.state.spawning.color_weights[color] != before[color]: actual_color = color
		if preview_color != actual_color:
			mismatches += 1
			print("REVIEW color seed=", run_seed, " preview=", preview_color, " applied=", actual_color)
	assert_eq(mismatches, 0, "卡面承诺的颜色应与实际权重修改一致")



func test_weight_refresh_keeps_color_and_uses_updated_values_without_rng() -> void:
	var run: RunController = _run()
	var effect: ColorWeightEffect = ColorWeightEffect.new()
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var frozen: SkillTarget = effect.freeze(context, run.state.rewards.target_random)
	var old_value: int = frozen.value_before
	run.state.spawning.color_weights[frozen.color] += 2
	var rng_before: int = run.state.rewards.target_random.state
	context = SkillRules.effect_context(run.state)
	var refreshed: SkillTarget = effect.refresh_after_previous(context, frozen, run.state.rewards.target_random)
	assert_eq(refreshed.color, frozen.color)
	assert_eq(refreshed.value_before, old_value + 2)
	assert_eq(refreshed.value_after, old_value + 4)
	assert_eq(frozen.value_before, old_value)
	assert_eq(run.state.rewards.target_random.state, rng_before)
	assert_eq(effect.build(context, refreshed).error, "")

func test_nested_offer_and_apply_preserve_displayed_weight_color() -> void:
	var run: RunController = _run()
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [ColorWeightEffect.new()]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [inner]
	var frozen: CompositeSkillTarget = outer.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	var nested: CompositeSkillTarget = frozen.leaf_targets[0] as CompositeSkillTarget
	var color: int = nested.leaf_targets[0].color
	var before: int = run.state.spawning.color_weights[color]
	var cursor: int = run.state.rewards.target_random.state
	assert_eq(AbilityEffectRunner.apply_skill_effect(run, outer, frozen, SkillApplyResult.new()), "")
	assert_eq(run.state.spawning.color_weights[color], before + 2)
	assert_eq(run.state.rewards.target_random.state, cursor)