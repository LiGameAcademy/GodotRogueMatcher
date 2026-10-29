extends GutTest

class CountingDye extends DyeMaterialEffect:
	var samples: int = 0
	func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
		samples += 1
		return super.freeze(context, random)

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	for index: int in range(9):
		run.state.rules.place_piece(Vector2i((index % 3) * 3, (index / 3) * 3), index % 3)
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func _skill(effect: SkillEffect) -> SkillDefinition:
	var ability: AbilityDefinition = AbilityDefinition.new()
	ability.ability_id = &"review_acquire"
	ability.event_type = &"skill_acquired"
	ability.effect = effect
	var level: SkillLevelDefinition = SkillLevelDefinition.new()
	level.level = 1
	level.abilities = [ability]
	var skill: SkillDefinition = SkillDefinition.new()
	skill.skill_id = &"review_target_fixture"
	skill.levels = [level]
	skill.maximum_level = 1
	return skill

func _offer(run: RunController, skill: SkillDefinition) -> SkillOffer:
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([skill])
	return generator.generate(run)

func _choose(run: RunController, offer: SkillOffer, color: int = -1) -> SkillApplyResult:
	return SkillRules.apply(run, offer.offer_id, offer.choices[0].skill_id, color)

func test_formal_offer_does_not_sample_dynamic_subtree_and_choice_samples_each_once() -> void:
	var run: RunController = _run()
	var first: CountingDye = CountingDye.new()
	var second: CountingDye = CountingDye.new()
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [first, second]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [RefillCountEffect.new(), inner]
	var skill: SkillDefinition = _skill(outer)
	var cursor: int = run.state.rewards.target_random.state
	var offer: SkillOffer = _offer(run, skill)
	assert_not_null(offer)
	if offer == null: return
	assert_eq(first.samples, 0)
	assert_eq(second.samples, 0)
	assert_eq(run.state.rewards.target_random.state, cursor)
	assert_eq(RewardOfferRules.target_rejection(run.state, skill, offer.targets[skill.skill_id]), "")
	assert_eq(first.samples, 0)
	var result: SkillApplyResult = _choose(run, offer)
	assert_true(result.success, result.error)
	assert_eq(first.samples, 1)
	assert_eq(second.samples, 1)
	cursor = run.state.rewards.target_random.state
	assert_false(_choose(run, offer).success)
	assert_eq(run.state.rewards.target_random.state, cursor)

func test_each_declared_dynamic_selector_samples_from_post_clear_board_once() -> void:
	var line: ClearMaterialEffect = ClearMaterialEffect.new()
	line.selector = ClearMaterialEffect.Selector.LINE
	var leaves: Array[ChoiceEffect] = [PercentClearEffect.new(), ThinMaterialEffect.new(), line, AssignFuseEffect.new()]
	for leaf: ChoiceEffect in leaves:
		var run: RunController = _run()
		var clear: ClearMaterialEffect = ClearMaterialEffect.new()
		var composite: CompositeEffect = CompositeEffect.new()
		composite.children = [clear, leaf]
		var skill: SkillDefinition = _skill(composite)
		var cursor: int = run.state.random_streams.stream(&"effect_execution").state
		var offer: SkillOffer = _offer(run, skill)
		assert_not_null(offer)
		if offer == null: continue
		var frozen: CompositeSkillTarget = offer.targets[skill.skill_id] as CompositeSkillTarget
		assert_true(frozen.leaf_targets[1].deferred)
		assert_true(frozen.leaf_targets[1].piece_ids.is_empty())
		assert_eq(run.state.random_streams.stream(&"effect_execution").state, cursor)
		var expected: RunController = _run()
		for piece: PieceState in expected.state.rules.state.get_snapshot():
			if piece.match_color == 0: expected.state.rules.remove_piece(piece.piece_id)
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.state = cursor
		var selected: SkillTarget = leaf.freeze(SkillRules.effect_context(expected.state), random)
		var result: SkillApplyResult = _choose(run, offer, 0)
		assert_true(result.success, result.error)
		assert_eq(run.state.random_streams.stream(&"effect_execution").state, random.state)
		if leaf is AssignFuseEffect:
			assert_eq(result.marked_ids, selected.piece_ids)
		else:
			for id: int in selected.piece_ids: assert_null(run.state.rules.state.get_piece(id))
			assert_eq(run.state.rules.state.get_piece_count(), 6 - selected.piece_ids.size())

func test_preview_snapshot_and_missing_color_do_not_sample_dynamic_target() -> void:
	var run: RunController = _run()
	var leaf: CountingDye = CountingDye.new()
	var composite: CompositeEffect = CompositeEffect.new()
	composite.children = [ClearMaterialEffect.new(), leaf]
	var skill: SkillDefinition = _skill(composite)
	var offer: SkillOffer = _offer(run, skill)
	assert_not_null(offer)
	if offer == null: return
	var cursor: int = run.state.rewards.target_random.state
	var before: Dictionary = RunSnapshot.capture(run)
	var preview: String = SkillChoiceText.compact_preview(skill, offer.targets[skill.skill_id].copy())
	assert_true(preview.contains(TranslationServer.translate("目标在执行时选择")))
	assert_true(before.offer.targets[String(skill.skill_id)].leaves[1].deferred)
	assert_false(_choose(run, offer).success)
	assert_eq(leaf.samples, 0)
	assert_eq(run.state.rewards.target_random.state, cursor)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), RunSnapshot.canonical(before))

class FixedDye extends DyeMaterialEffect:
	var ids: Array[int] = []
	var selected: int = 0
	func _init() -> void:
		target_policy = TargetPolicy.FIXED
	func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
		var target: SkillTarget = SkillTarget.new()
		target.piece_ids = ids.duplicate()
		target.color = selected
		return target

class FixedFuse extends AssignFuseEffect:
	var id: int
	func _init() -> void:
		target_policy = TargetPolicy.FIXED
	func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
		var target: SkillTarget = SkillTarget.new()
		target.piece_ids = [id]
		return target

func _boundary_run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 2), 0)
	run.abilities.assign_fuse(run.state.rules.state.get_piece_at(Vector2i(3, 2)).piece_id)
	run.state.rules.place_piece(Vector2i(5, 2), 1)
	run.state.rules.place_piece(Vector2i(3, 3), 2)
	run.state.rules.place_piece(Vector2i(3, 4), 2)
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func test_b03_b04_formal_offer_fixed_invalid_target_skip_and_strict_error() -> void:
	for skip: bool in [false, true]:
		var run: RunController = _boundary_run()
		var a: PieceState = run.state.rules.state.get_piece_at(Vector2i(5, 2))
		var dye: FixedDye = FixedDye.new()
		dye.ids = [a.piece_id]
		var fuse: FixedFuse = FixedFuse.new()
		fuse.id = a.piece_id
		var composite: CompositeEffect = CompositeEffect.new()
		composite.children = [dye, fuse]
		if skip: composite.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
		var offer: SkillOffer = _offer(run, _skill(composite))
		assert_not_null(offer)
		if offer == null: continue
		var cursor: int = run.state.rewards.target_random.state
		var result: SkillApplyResult = _choose(run, offer)
		assert_eq(result.success, skip)
		assert_eq(run.state.ledger.total, 50)
		assert_null(run.state.rules.state.get_piece(a.piece_id))
		assert_eq(run.state.rewards.target_random.state, cursor)
		assert_eq(run.state.rewards.consumed_count, 1 if skip else 0)
		if skip:
			assert_eq(result.target_changes[0].outcome, "empty")
			assert_false(run.state.explosion.fuse_unlocked, "空目标跳过不能安装附引信能力")
			assert_null(run.state.rules.state.get_piece_at(Vector2i(3, 3)))
			assert_not_null(run.state.rules.state.get_piece_at(Vector2i(3, 4)))
		else:
			assert_eq(result.outcome, &"error")
			assert_eq(run.state.phase, RunState.Phase.ERROR)
			assert_not_null(run.state.rules.state.get_piece_at(Vector2i(3, 3)))
			var traces: Array[Dictionary] = run.state.ability_events.take_traces()
			assert_eq(traces.size(), 1)
			if not traces.is_empty():
				assert_true(traces[0].get("interrupted", false))
				assert_eq(traces[0].get("interruption_reason"), &"composite_aborted")
			assert_false(_choose(run, offer).success)
		assert_true(run.abilities.flush_held_blasts().is_empty())

func test_partial_fixed_targets_revalidate_and_bad_color_is_not_swallowed() -> void:
	for corrupt: bool in [false, true]:
		var run: RunController = _boundary_run()
		var a: PieceState = run.state.rules.state.get_piece_at(Vector2i(5, 2))
		var q: PieceState = run.state.rules.state.get_piece_at(Vector2i(3, 3))
		var dye: FixedDye = FixedDye.new()
		dye.ids = [a.piece_id]
		var second: FixedDye = FixedDye.new()
		second.ids = [a.piece_id, q.piece_id]
		second.selected = 99 if corrupt else 1
		var multiplier: DemolitionStatEffect = DemolitionStatEffect.new()
		multiplier.stat = DemolitionStatEffect.Stat.MULTIPLIER
		var composite: CompositeEffect = CompositeEffect.new()
		composite.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
		composite.children = [dye, second, multiplier]
		var offer: SkillOffer = _offer(run, _skill(composite))
		assert_not_null(offer)
		if offer == null: continue
		var result: SkillApplyResult = _choose(run, offer)
		assert_eq(result.success, not corrupt)
		assert_eq(run.state.explosion.multiplier_level, 0 if corrupt else 1)
		assert_eq(run.state.ledger.total, 0 if corrupt else 50)
		if not corrupt:
			assert_eq(result.target_changes[0].remaining, [q.piece_id])
			assert_eq(result.target_changes[0].outcome, "partial")
		else:
			assert_eq(result.error, "染色目标配置无效")
			assert_eq(result.outcome, &"rejected")

func test_skip_policy_does_not_erase_budget_rejection() -> void:
	var run: RunController = _boundary_run()
	run.abilities.config = run.abilities.config.duplicate() as ExplosionConfig
	run.abilities.config.event_budget = 0
	var dye: FixedDye = FixedDye.new()
	dye.ids = [run.state.rules.state.get_piece_at(Vector2i(5, 2)).piece_id]
	var composite: CompositeEffect = CompositeEffect.new()
	composite.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
	composite.children = [dye, DemolitionStatEffect.new()]
	var offer: SkillOffer = _offer(run, _skill(composite))
	assert_not_null(offer)
	if offer == null: return
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var result: SkillApplyResult = _choose(run, offer)
	assert_false(result.success)
	assert_eq(result.outcome, &"rejected")
	assert_string_contains(result.error, "budget")
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
