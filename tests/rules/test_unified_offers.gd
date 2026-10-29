extends GutTest

## FG01-FG10 and weighted-pool contracts; fixed rule fixtures, not calibration samples.
func _run(seed_value: int = 86) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.state.pending_rewards = 1
	run.state.rewards.consumed_count = 4
	run.enter_rewards()
	return run

func _skill(id: StringName) -> SkillDefinition:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id == id: return skill
	return null

func _explain(run: RunController, id: StringName) -> Dictionary:
	var skill: SkillDefinition = _skill(id)
	var build: SkillBuildSnapshot = SkillOfferGenerator.build_snapshot(run.state)
	var reason: String = SkillRules.rejection(run.state, skill, run.abilities.config, -1.0, build)
	return OfferWeightRules.evaluate(skill, build, run.state.rewards.consumed_count + 1, reason, SkillOfferGenerator.CONFIG)

func _take(run: RunController, id: StringName) -> void:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([_skill(id)])
	var offer: SkillOffer = generator.generate(run)
	assert_not_null(offer, generator.last_error)
	if offer == null: return
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, id)
	assert_true(result.success, result.error)

func test_all_actual_definitions_have_explicit_valid_traits_and_default_q() -> void:
	assert_eq(SkillOfferGenerator.CATALOG.size(), 52)
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		assert_eq(skill.validation_error(), "", String(skill.skill_id))
		assert_eq(skill.offer_traits.exception_multiplier, 1.0)
		assert_eq(int(skill.offer_traits.once_per_run) + int(skill.offer_traits.upgradeable) + int(skill.offer_traits.repeatable), 1)
	for id: StringName in [&"score_multiplier", &"match_extra", &"precision_reward", &"longline_reward"]:
		assert_true(_skill(id).offer_traits.affinity.is_empty())
		assert_true(_skill(id).offer_traits.payoffs.is_empty())

func test_fg01_persistent_supply_without_carrier_only_missing_first_payoff_is_boosted() -> void:
	var run: RunController = _run()
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	for id: StringName in [&"core_supply_up", &"blast_radius", &"core_radius"]:
		assert_eq(_explain(run, id).H, 1)
		assert_eq(_explain(run, id).fills_gap, 0)
	for id: StringName in [&"blast_extra", &"blast_reward"]:
		assert_eq(_explain(run, id).H, 1)
		assert_eq(_explain(run, id).fills_gap, 1)

func test_fg02_first_real_payoff_closes_both_blast_payoff_candidates_but_upgrade_stays_legal() -> void:
	var run: RunController = _run()
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	_take(run, &"blast_extra")
	for id: StringName in [&"blast_extra", &"blast_reward"]:
		assert_eq(_explain(run, id).H, 1)
		assert_eq(_explain(run, id).fills_gap, 0)

func test_fg03_real_instant_conversion_keeps_investment_after_departure_without_permanent_prerequisite() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i.ZERO, 1)
	_take(run, &"instant_core_transform")
	for piece: PieceState in run.state.rules.state.get_snapshot(): run.state.rules.remove_piece(piece.piece_id)
	assert_eq(_explain(run, &"core_drop").H, 1)
	assert_eq(_explain(run, &"core_drop").fills_gap, 1)
	assert_eq(_explain(run, &"core_supply_up").H, 0)
	assert_eq(_explain(run, &"core_supply_up").W, 0.0)
	assert_eq(_explain(run, &"instant_core_transform").fills_gap, 0)

func test_fg04_relay_needs_stock_persistent_seed_channel_is_a_gap_but_assign_is_not() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i.ZERO, 1)
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	run.state.explosion.fuse_unlocked = true
	run.state.explosion.upgrades[&"fuse_relay"] = 1
	for id: StringName in [&"core_fuse_payload", &"fuse_match_plant"]:
		assert_eq(_explain(run, id).H, 1)
		assert_eq(_explain(run, id).fills_gap, 1)
	assert_eq(_explain(run, &"assign_fuse").fills_gap, 0)
	run.state.explosion.upgrades[&"fuse_match_plant"] = 1
	assert_eq(_explain(run, &"core_fuse_payload").fills_gap, 0)

func test_fg05_line_supply_without_carrier_and_real_first_line_payoff() -> void:
	var run: RunController = _run()
	run.state.line_clear.row_unlocked = true
	assert_eq(_explain(run, &"line_row_span").fills_gap, 0)
	assert_eq(_explain(run, &"line_clear_score").fills_gap, 1)
	_take(run, &"line_clear_score")
	assert_eq(_explain(run, &"line_clear_score").H, 1)
	assert_eq(_explain(run, &"line_clear_score").fills_gap, 0)

func test_fg06_axis_extension_is_not_missing_supply_and_instant_history_is() -> void:
	var row: RunController = _run()
	row.state.line_clear.row_unlocked = true
	assert_eq(_explain(row, &"line_column_drop").fills_gap, 0)
	var instant: RunController = _run()
	instant.state.rules.place_piece(Vector2i.ZERO, 1)
	_take(instant, &"instant_row_transform")
	assert_eq(_explain(instant, &"line_row_drop").fills_gap, 1)
	var column: RunController = _run()
	column.state.line_clear.column_unlocked = true
	assert_eq(_explain(column, &"line_row_drop").fills_gap, 0)

func test_fg07_mixed_routes_keep_independent_first_payoff_gaps_and_generic_does_not_close_them() -> void:
	var run: RunController = _run()
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	run.state.line_clear.row_unlocked = true
	for id: StringName in [&"score_multiplier", &"precision_reward", &"longline_reward"]:
		assert_eq(_explain(run, id).related, 0)
		assert_eq(_explain(run, id).fills_gap, 0)
	assert_eq(_explain(run, &"blast_extra").fills_gap, 1)
	assert_eq(_explain(run, &"line_clear_score").fills_gap, 1)
	_take(run, &"blast_extra")
	assert_eq(_explain(run, &"blast_reward").fills_gap, 0)
	assert_eq(_explain(run, &"line_clear_score").fills_gap, 1)

func test_fg08_synthetic_registered_bridge_caps_related_and_gap_at_one() -> void:
	var run: RunController = _run()
	run.state.rewards.acquired[&"instant_core_transform"] = 10
	run.state.rewards.acquired[&"instant_row_transform"] = 20
	var fixture: SkillDefinition = _skill(&"core_drop").duplicate(true) as SkillDefinition
	fixture.offer_traits.affinity = [&"blast", &"line"]
	fixture.offer_traits.supplies = [&"blast", &"line"]
	fixture.offer_traits.roles = [&"bridge"]
	var build: SkillBuildSnapshot = SkillOfferGenerator.build_snapshot(run.state)
	var row: Dictionary = OfferWeightRules.evaluate(fixture, build, 1, "", SkillOfferGenerator.CONFIG)
	assert_eq(row.gap_routes.size(), 2)
	assert_eq(row.related, 1)
	assert_eq(row.fills_gap, 1)
	assert_eq(row.factor_before_clamp, 1.5)
	assert_eq(row.Q, 1.0)
	assert_eq(_skill(&"core_drop").offer_traits.supplies, [&"blast"])

func test_fg09_no_investment_or_shape_unlock_affinity_and_hard_gate_cannot_be_rescued() -> void:
	var run: RunController = _run()
	assert_eq(_explain(run, &"core_drop").fills_gap, 0)
	assert_eq(_explain(run, &"blast_extra").H, 0)
	assert_eq(_explain(run, &"blast_extra").fills_gap, 0)
	var t: SkillDefinition = ShapeUnlockDemo.t()
	var before: Dictionary = OfferWeightRules.evaluate(t, SkillOfferGenerator.build_snapshot(run.state), 5, "", SkillOfferGenerator.CONFIG)
	assert_true(run.state.rules.shape_unlocks.unlock(preload("res://gameplay/board/matching/l_template.tres"), 1))
	var after: Dictionary = OfferWeightRules.evaluate(t, SkillOfferGenerator.build_snapshot(run.state), 5, "", SkillOfferGenerator.CONFIG)
	assert_eq(before, after)
	assert_eq(after.related, 0)
	assert_eq(after.fills_gap, 0)

func test_fg10_frozen_projection_does_not_count_other_candidates_or_reopen_and_isolates_runs() -> void:
	var run: RunController = _run()
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([_skill(&"blast_extra"), _skill(&"blast_reward")])
	var offer: SkillOffer = generator.generate(run)
	assert_eq(offer.explanations[&"blast_extra"].fills_gap, 1)
	assert_eq(offer.explanations[&"blast_reward"].fills_gap, 1)
	var before: String = RunSnapshot.canonical(RunSnapshot.offer_data(offer))
	var streams: Dictionary = run.state.random_streams.data()
	assert_same(generator.generate(run), offer)
	assert_eq(run.state.random_streams.data(), streams)
	var copy: SkillOffer = offer.snapshot()
	copy.explanations[&"blast_extra"].W = 123.0
	copy.slot_log[0].weights.clear()
	copy.build_snapshot.invested.clear()
	assert_eq(RunSnapshot.canonical(RunSnapshot.offer_data(offer)), before)
	assert_false(SkillOfferGenerator.build_snapshot(_run().state).invested.has(&"blast"))
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"blast_extra")
	assert_true(result.success, result.error)
	assert_eq(_explain(run, &"blast_reward").fills_gap, 0)

func test_slot_denominators_ascii_order_and_strict_cumulative_selection_are_recomputable() -> void:
	var catalog: Array[SkillDefinition] = [_skill(&"score_multiplier"), _skill(&"precision_reward"), _skill(&"match_extra"), _skill(&"longline_reward")]
	var first: SkillOfferGenerator = SkillOfferGenerator.new()
	first.set_catalog(catalog)
	var a: SkillOffer = first.generate(_run())
	catalog.reverse()
	var second: SkillOfferGenerator = SkillOfferGenerator.new()
	second.set_catalog(catalog)
	var b: SkillOffer = second.generate(_run())
	assert_eq(a.generation_order, b.generation_order)
	assert_eq(a.slot_log, b.slot_log)
	var used: Array[StringName] = []
	for slot: Dictionary in a.slot_log:
		var denominator: float = 0.0
		var keys: Array = slot.weights.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		for id: StringName in keys:
			assert_false(used.has(id))
			denominator += slot.weights[id]
		assert_almost_eq(denominator, float(slot.denominator), 0.0000001)
		var accumulated: float = 0.0
		for id: StringName in keys:
			accumulated += slot.weights[id]
			if accumulated > float(slot.sample) * denominator:
				assert_eq(id, slot.selected)
				break
		used.append(slot.selected)

func test_utility_quota_short_group_does_not_fallback_or_repeat_and_can_be_disabled() -> void:
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([_skill(&"refill_less"), _skill(&"refill_more")])
	var offer: SkillOffer = generator.generate(_run())
	assert_eq(offer.choices.size(), 1)
	assert_eq(offer.slot_log[1].denominator, 0.0)
	assert_eq(offer.slot_log[1].quota_excluded.size(), 1)
	generator.config = SkillOfferGenerator.CONFIG.duplicate(true) as OfferConfig
	generator.config.maximum_utility_picks = -1
	assert_eq(generator.generate(_run()).choices.size(), 2)
	assert_eq(SkillOfferGenerator.CONFIG.maximum_utility_picks, 1)

func test_invalid_policy_mapping_or_config_rejects_before_all_streams_and_identity() -> void:
	for invalid: int in range(4):
		var run: RunController = _run()
		var skill: SkillDefinition = _skill(&"score_multiplier").duplicate(true) as SkillDefinition
		if invalid == 0: skill.offer_traits = null
		if invalid == 1: skill.offer_traits.once_per_run = true
		if invalid == 2: skill.offer_traits.needs = [&"unknown"]
		if invalid == 3: skill.offer_traits.exception_multiplier = 0.0
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var generator: SkillOfferGenerator = SkillOfferGenerator.new()
		generator.set_catalog([skill])
		assert_null(generator.generate(run))
		assert_false(generator.last_error.is_empty())
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_flat_trial_curve_and_explicit_steps_use_only_successful_choice_index() -> void:
	var config: OfferConfig = SkillOfferGenerator.CONFIG.duplicate(true) as OfferConfig
	assert_eq(config.validation_error(), "")
	for rarity: int in range(5): assert_eq(config.base_weight(rarity, 1), config.base_weight(rarity, 99))
	var step: OfferRarityStep = OfferRarityStep.new()
	step.first_choice = 3
	step.weights = [2.0, 2.0, 2.0, 2.0, 2.0]
	config.rarity_steps = [step]
	assert_eq(config.base_weight(0, 2), 1.0)
	assert_eq(config.base_weight(0, 3), 2.0)
	config.rarity_steps.append(step)
	assert_false(config.validation_error().is_empty())
	assert_true(SkillOfferGenerator.CONFIG.rarity_steps.is_empty())
