extends GutTest

var run: RunController
var generator: SkillOfferGenerator

func before_each() -> void:
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.enter_rewards()
	run.state.pending_rewards = 3
	generator = SkillOfferGenerator.new()

func test_first_offer_has_starter_and_distinct_legal_ids() -> void:
	run.state.rules.place_piece(Vector2i.ZERO, 0)
	var offer: SkillOffer = generator.generate(run)
	assert_eq(offer.choices.size(), 3)
	assert_true(offer.generation_order[0] in [&"core_drop", &"match_dye_echo"])
	assert_true(_contains(offer, &"core_drop"))
	for skill: SkillDefinition in offer.choices: assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "")
	assert_eq(run.state.pending_rewards, 3)

func test_empty_board_uses_fallback_and_freezes_offer() -> void:
	var board_random: int = run.state.random.state
	var offer: SkillOffer = generator.generate(run)
	var candidate_random: int = run.state.rewards.candidate_random.state
	assert_true(_contains(offer, &"core_drop"))
	assert_false(_contains(offer, &"assign_fuse"))
	assert_same(generator.generate(run), offer)
	assert_eq(run.state.rewards.candidate_random.state, candidate_random)
	assert_eq(run.state.random.state, board_random)
	assert_true(SkillRules.apply(run, offer.offer_id, &"core_drop").success)
	assert_eq(run.state.pending_rewards, 2)
	assert_eq(run.state.turn_count, 0)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_false(SkillRules.apply(run, offer.offer_id, &"core_drop").success)
	assert_eq(run.state.rules.state.get_piece_count(), 1)

func test_invalid_target_preserves_every_rule_state_and_reward() -> void:
	var offer: SkillOffer = generator.generate(run)
	var target: Vector2i = offer.targets[&"core_drop"].coordinate
	run.state.rules.place_piece(target, 3)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"core_drop")
	assert_false(result.success)
	assert_eq(run.state.pending_rewards, 3)
	assert_eq(run.state.rewards.consumed_count, 0)
	assert_eq(run.state.action_id, 0)
	assert_false(run.state.explosion.unlocked)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_same(run.state.rewards.active_offer, offer)

func test_fuse_marks_actual_one_target_and_preserves_color() -> void:
	var piece: PieceState = run.state.rules.place_piece(Vector2i.ZERO, 4)
	var offer: SkillOffer = generator.generate(run)
	offer.choices[0] = _definition(&"assign_fuse")
	var target: SkillTarget = SkillTarget.new()
	target.piece_ids = [piece.piece_id]
	offer.targets[&"assign_fuse"] = target
	assert_eq(offer.targets[&"assign_fuse"].piece_ids, [piece.piece_id])
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"assign_fuse")
	assert_true(result.success)
	assert_eq(result.marked_ids.size(), 1)
	assert_eq(run.state.rules.state.get_piece(piece.piece_id).match_color, 4)
	assert_true(run.state.explosion.unlocked)
	assert_eq(SkillOfferGenerator.build_profile(run.state)[&"exp"], 1.0)
	var next: SkillOffer = generator.generate(run)
	assert_false(_contains(next, &"assign_fuse"))
	assert_eq(next.reward_id, 2)

func test_weight_example_and_live_driver_compensation() -> void:
	run.abilities.add_core(Vector2i.ZERO)
	run.state.rewards.acquired[&"core_drop"] = 1
	run.state.rewards.acquired[&"assign_fuse"] = 1
	var profile: Dictionary[StringName, float] = SkillOfferGenerator.build_profile(run.state)
	assert_eq(profile[&"exp"], 2.0)
	assert_almost_eq(SkillOfferGenerator.weight(run.state, _definition(&"blast_reward"), profile), 22.4 * 0.65, 0.0001)
	assert_almost_eq(SkillOfferGenerator.weight(run.state, _definition(&"assign_fuse"), profile), 22.0, 0.0001)
	run.state.explosion.instances.clear()
	run.state.rewards.previous_unselected = [&"assign_fuse"]
	assert_almost_eq(SkillOfferGenerator.weight(run.state, _definition(&"assign_fuse"), profile), 23.1, 0.0001)
	assert_eq(SkillOfferGenerator.build_profile(run.state)[&"exp"], 2.0)

func test_full_caps_exclude_upgrades_and_core_unique() -> void:
	run.abilities.add_core(Vector2i.ZERO)
	run.state.explosion.radius_level = 1
	run.state.explosion.reward_level = 3
	var offer: SkillOffer = generator.generate(run)
	assert_false(_contains(offer, &"core_drop"))
	assert_false(_contains(offer, &"blast_radius"))
	assert_false(_contains(offer, &"blast_reward"))
	assert_false(_contains(offer, &"assign_fuse"))
	assert_eq(offer.choices.size(), 3)
	for skill: SkillDefinition in offer.choices: assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "")

func test_current_and_future_fuses_share_upgraded_radius_only_in_same_run() -> void:
	run.abilities.assign_fuse(run.state.rules.place_piece(Vector2i.ZERO, 0).piece_id)
	run.state.explosion.core_pool_unlocked = true
	var offer: SkillOffer = generator.generate(run)
	# 受控候选用于验证具体应用，不依赖随机恰好展示某项。
	offer.choices[0] = _definition(&"blast_radius")
	offer.targets[&"blast_radius"] = SkillTarget.new()
	assert_true(SkillRules.apply(run, offer.offer_id, &"blast_radius").success)
	assert_eq(run.state.explosion.radius_level, 1)
	var other: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	assert_eq(other.state.explosion.radius_level, 0)
	assert_eq(AbilityResolver.DEFAULT_CONFIG.base_radius, 1)

func test_core_landing_resolves_match_without_movement_and_records_once() -> void:
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 1)
	var offer: SkillOffer = generator.generate(run)
	offer.targets[&"core_drop"].coordinate = Vector2i(4, 0)
	offer.targets[&"core_drop"].color = 1
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"core_drop")
	assert_true(result.success)
	assert_eq(result.matches.size(), 2)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.state.turn_count, 0)
	assert_eq(run.state.pending_rewards, 2)
	assert_false(_contains(generator.generate(run), &"core_drop"))
	assert_true(run.state.explosion.core_pool_unlocked)

func test_core_budget_rejection_does_not_insert_or_consume() -> void:
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 1)
	var config: ExplosionConfig = AbilityResolver.DEFAULT_CONFIG.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities = AbilityResolver.new(run.state, config)
	var offer: SkillOffer = generator.generate(run)
	offer.targets[&"core_drop"].coordinate = Vector2i(4, 0)
	offer.targets[&"core_drop"].color = 1
	assert_false(SkillRules.apply(run, offer.offer_id, &"core_drop").success)
	assert_eq(run.state.rules.state.get_piece_count(), 4)
	assert_eq(run.state.pending_rewards, 3)
	assert_eq(run.state.ledger.total, 0)
	assert_false(run.state.explosion.unlocked)

func test_fixed_seed_offers_targets_and_board_stream_are_independent() -> void:
	var other: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	other.state.pending_rewards = 3
	other.state.random.randi()
	other.state.rewards.display_random.randi()
	var first: SkillOffer = generator.generate(run)
	var second: SkillOffer = generator.generate(other)
	assert_eq(first.generation_order, second.generation_order)
	assert_eq(first.targets[&"core_drop"].coordinate, second.targets[&"core_drop"].coordinate)
	assert_eq(first.candidate_state_after, second.candidate_state_after)

func test_ten_thousand_seeds_never_repeat_ids_or_offer_illegal_upgrades() -> void:
	var invalid: int = 0
	for seed_value: int in range(10000):
		var sample: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
		sample.state.pending_rewards = 1
		sample.state.rules.place_piece(Vector2i.ZERO, 0)
		var offer: SkillOffer = generator.generate(sample)
		var unique: Array[StringName] = []
		if offer.choices.size() != 3 or offer.generation_order[0] not in [&"core_drop", &"match_dye_echo"]: invalid += 1
		for skill: SkillDefinition in offer.choices:
			if unique.has(skill.skill_id) or not SkillRules.rejection(sample.state, skill, sample.abilities.config).is_empty(): invalid += 1
			unique.append(skill.skill_id)
	assert_eq(invalid, 0)

func _definition(id: StringName) -> SkillDefinition:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id == id: return skill
	return null

func _contains(offer: SkillOffer, id: StringName) -> bool:
	for skill: SkillDefinition in offer.choices:
		if skill.skill_id == id: return true
	return false
