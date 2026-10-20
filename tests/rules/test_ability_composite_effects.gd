extends GutTest

func _run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)

func _skill(effect: SkillEffect, skill_id: StringName = &"composite_acceptance") -> SkillDefinition:
	var ability: AbilityDefinition = AbilityDefinition.new()
	ability.ability_id = &"composite_acquire"
	ability.event_type = &"skill_acquired"
	ability.effect = effect
	var level: SkillLevelDefinition = SkillLevelDefinition.new()
	level.level = 1
	level.abilities = [ability]
	var skill: SkillDefinition = SkillDefinition.new()
	skill.skill_id = skill_id
	skill.title = "Composite Acceptance"
	skill.is_persistent = true
	skill.maximum_level = 1
	skill.levels = [level]
	skill.base_weight = 1.0
	return skill

func _refill_weight_composite() -> CompositeEffect:
	var refill: RefillCountEffect = RefillCountEffect.new()
	refill.delta = -1
	refill.batches = 3
	var weight: ColorWeightEffect = ColorWeightEffect.new()
	weight.delta = 2
	var composite: CompositeEffect = CompositeEffect.new()
	composite.children = [refill, weight]
	return composite

func _clear_dye_composite() -> CompositeEffect:
	var clear: ClearMaterialEffect = ClearMaterialEffect.new()
	clear.selector = ClearMaterialEffect.Selector.COLOR
	var dye: DyeMaterialEffect = DyeMaterialEffect.new()
	var composite: CompositeEffect = CompositeEffect.new()
	composite.children = [clear, dye]
	return composite

func _offer(run: RunController, skill: SkillDefinition) -> SkillOffer:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill, run.state.rewards.target_random)
	run.state.rewards.active_offer = offer
	return offer

func test_leaf2_reads_state_after_leaf1_commit() -> void:
	var run: RunController = _run()
	var before_refill: int = run.state.next_refill_count()
	var before_weights: Array = run.state.spawning.color_weights.duplicate()
	var skill: SkillDefinition = _skill(_refill_weight_composite())
	assert_eq(skill.validation_error(), "")
	var offer: SkillOffer = _offer(run, skill)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert_true(result.success, result.error)
	assert_eq(run.state.next_refill_count(), before_refill - 1)
	var changed: bool = false
	for color: int in range(before_weights.size()):
		if run.state.spawning.color_weights[color] != before_weights[color]:
			changed = true
			assert_eq(run.state.spawning.color_weights[color], before_weights[color] + 2)
	assert_true(changed)
	assert_eq(RunSnapshot.RULES_VERSION, "run-commands-v36-composite-boundaries")

func test_clear_then_dye_defers_descendant_blasts_until_composite_done() -> void:
	var run: RunController = _run()
	# Keep at least two colors after clearing color 0 so the dye leaf can still reject-check.
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 0), 0)
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 1), 1)
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 2), 2)
	var fuse_owner: PieceState = null
	for candidate: PieceState in run.state.rules.state.get_snapshot():
		if candidate.coordinate == Vector2i(0, 0): fuse_owner = candidate
	assert_not_null(fuse_owner)
	run.abilities.assign_fuse(fuse_owner.piece_id)
	var skill: SkillDefinition = _skill(_clear_dye_composite())
	var offer: SkillOffer = _offer(run, skill)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id, 0)
	assert_true(result.success, result.error)
	assert_eq(run.abilities._held_blasts.size(), 0)
	assert_gt(result.removed.size(), 0)
	assert_true(run.state.skill_instances.has(skill.skill_id))
	assert_false(run.state.explosion.instances.has(fuse_owner.piece_id))

func test_fixed_target_reject_fails_before_mutating() -> void:
	var run: RunController = _run()
	var skill: SkillDefinition = _skill(_refill_weight_composite())
	var offer: SkillOffer = _offer(run, skill)
	var composite_target: CompositeSkillTarget = offer.targets[skill.skill_id] as CompositeSkillTarget
	composite_target.leaf_targets[0].value_before = -999
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert_false(result.success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(run.state.pending_rewards, 1)

func test_fixed_target_skip_drops_invalid_ids() -> void:
	var run: RunController = _run()
	for x: int in range(3):
		run.state.rules.place_piece(Vector2i(x, 4), 2)
		run.state.rules.place_piece(Vector2i(x, 5), 3)
	var composite: CompositeEffect = _clear_dye_composite()
	composite.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
	var skill: SkillDefinition = _skill(composite)
	var offer: SkillOffer = _offer(run, skill)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id, 2)
	assert_true(result.success, result.error)

func test_composite_validation_rejects_cycle_depth_and_empty() -> void:
	var empty: CompositeEffect = CompositeEffect.new()
	assert_string_contains(empty.validation_error(), "missing children")
	var cyclic: CompositeEffect = CompositeEffect.new()
	cyclic.children = [cyclic]
	assert_string_contains(cyclic.validation_error(), "cycle")
	cyclic.children.clear()
	var cursor: CompositeEffect = CompositeEffect.new()
	cursor.children = [RefillCountEffect.new()]
	for _i: int in range(9):
		var next: CompositeEffect = CompositeEffect.new()
		next.children = [cursor]
		cursor = next
	assert_string_contains(cursor.validation_error(), "too deep")
	var bad_child: CompositeEffect = CompositeEffect.new()
	bad_child.children = [ExplodeEffect.new()]
	assert_string_contains(bad_child.validation_error(), "unsupported")
	var ability: AbilityDefinition = AbilityDefinition.new()
	ability.ability_id = &"x"
	ability.event_type = &"skill_acquired"
	ability.effect = CompositeEffect.new()
	assert_string_contains(AbilityTriggerAdapter.validation_error(ability), "missing children")

func test_acceptance_skill_uses_generic_apply_without_skill_id_branch() -> void:
	var run: RunController = _run()
	var skill: SkillDefinition = _skill(_refill_weight_composite(), &"no_special_branch")
	var offer: SkillOffer = _offer(run, skill)
	assert_true(SkillRules.apply(run, offer.offer_id, skill.skill_id).success)
	assert_eq(run.state.skill_instances[skill.skill_id].level, 1)
	assert_true(run.state.skill_instances[skill.skill_id].abilities[0].definition.effect is CompositeEffect)

func test_single_leaf_core_drop_still_applies_through_runner() -> void:
	var run: RunController = _run()
	var core: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = 1
	offer.choices = [core]
	offer.targets[core.skill_id] = SkillRules.freeze_target(run.state, core)
	run.state.rewards.active_offer = offer
	assert_true(SkillRules.apply(run, offer.offer_id, core.skill_id).success)
	assert_true(run.state.explosion.core_pool_unlocked)

func test_composite_clear_color_picker_reads_clear_leaf_groups() -> void:
	var run: RunController = _run()
	for color: int in range(3):
		run.state.rules.place_piece(Vector2i(color, 0), color)
	var composite: CompositeEffect = _clear_dye_composite()
	var frozen: CompositeSkillTarget = composite.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	assert_true(frozen.color_groups.is_empty())
	var picker: SkillTarget = frozen.color_picker_source()
	assert_ne(picker, frozen)
	assert_eq(picker.color_groups.size(), 5)
	assert_eq(picker.color_groups[0].size(), 1)
	assert_eq(picker.color_groups[1].size(), 1)
	assert_eq(picker.color_groups[2].size(), 1)
	assert_true(preload("res://gameplay/progression/content/composite_clear_dye.tres").requires_color_choice())
