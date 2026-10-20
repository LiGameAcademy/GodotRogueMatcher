extends GutTest

## #62: former Action-branch skills keep behavior through ChoiceEffect / levels.

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 62)
	run.state.phase = RunState.Phase.INPUT
	return run

func _skill(id: StringName) -> SkillDefinition:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id == id: return skill
	return null

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

func test_assign_fuse_marks_and_unlocks_fuse_route() -> void:
	var run: RunController = _run()
	for x: int in range(3):
		run.state.rules.place_piece(Vector2i(x, 0), x)
	var skill: SkillDefinition = _skill(&"assign_fuse")
	assert_true(skill.acquisition_effect() is AssignFuseEffect)
	var offer: SkillOffer = _offer(run, skill)
	assert_true(SkillRules.apply(run, offer.offer_id, skill.skill_id).success)
	assert_true(run.state.explosion.fuse_unlocked)
	assert_eq(run.state.explosion.instances.size(), 2)

func test_thin_removes_without_scoring_or_blast() -> void:
	var run: RunController = _run()
	run.state.rewards.consumed_count = 2
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 0), 0)
	var before: int = run.state.rules.state.get_piece_count()
	var skill: SkillDefinition = _skill(&"instant_thin")
	assert_true(skill.acquisition_effect() is ThinMaterialEffect)
	var offer: SkillOffer = _offer(run, skill)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert_true(result.success, result.error)
	assert_eq(result.removed.size(), 3)
	assert_eq(run.state.rules.state.get_piece_count(), before - 3)
	assert_eq(run.state.ledger.total, 0)

func test_blast_radius_levels_and_stat_stay_synced() -> void:
	var run: RunController = _run()
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	var skill: SkillDefinition = _skill(&"blast_radius")
	assert_true(skill.acquisition_effect() is DemolitionStatEffect)
	assert_false(skill.levels.is_empty())
	var offer: SkillOffer = _offer(run, skill)
	assert_true(SkillRules.apply(run, offer.offer_id, skill.skill_id).success)
	assert_eq(run.state.explosion.radius_level, 1)
	assert_eq(SkillRules.level(run.state, skill), 1)
	assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "已满级")

func test_score_multiplier_repeat_via_choice_effect() -> void:
	var run: RunController = _run()
	var skill: SkillDefinition = _skill(&"score_multiplier")
	assert_true(skill.acquisition_effect() is DemolitionStatEffect)
	assert_true(skill.levels.is_empty())
	for expected: int in range(1, 3):
		var offer: SkillOffer = _offer(run, skill)
		assert_true(SkillRules.apply(run, offer.offer_id, skill.skill_id).success)
		assert_eq(run.state.explosion.multiplier_level, expected)

func test_catalog_every_skill_has_effect_root() -> void:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		assert_ne(skill.acquisition_effect(0), null, String(skill.skill_id))
		assert_true(skill.validation_error().is_empty(), "%s: %s" % [skill.skill_id, skill.validation_error()])
