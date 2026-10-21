extends GutTest

class ObservedFuse extends AssignFuseEffect:
	var observe: Callable
	func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
		observe.call(context)
		return super.build(context, target)

class DynamicProbe extends ChoiceEffect:
	var samples: int = 0
	func freeze(_context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
		samples += 1
		random.randi()
		return SkillTarget.new()
	func refresh_after_previous(context: ChoiceEffectContext, _frozen: SkillTarget, random: RandomNumberGenerator) -> SkillTarget:
		return freeze(context, random)
	func build(_context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		request.kind = ChoiceEffectRequest.Kind.REFILL
		request.delta = -1
		return request

class FailingLeaf extends ChoiceEffect:
	func rejection(_context: ChoiceEffectContext) -> String:
		return ""
	func build(context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		if context.material.size() < 2: request.error = "injected_post_leaf_failure"
		return request

func _boundary(nested: bool) -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	run.state.phase = RunState.Phase.REWARDS
	run.abilities.config = run.abilities.config.duplicate() as ExplosionConfig
	run.abilities.config.reward_per_target = 0
	run.abilities.config.bonus_per_blast = 0
	for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 2), 0)
	var source: PieceState = run.state.rules.state.get_piece_at(Vector2i(3, 2))
	assert_true(run.abilities.assign_fuse(source.piece_id))
	var a: PieceState = run.state.rules.place_piece(Vector2i(5, 2), 1)
	var q: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 2)
	var r: PieceState = run.state.rules.place_piece(Vector2i(3, 4), 2)
	var dye: DyeMaterialEffect = DyeMaterialEffect.new()
	var fuse: ObservedFuse = ObservedFuse.new()
	var checkpoints: Array[Dictionary] = []
	fuse.observe = func(context: ChoiceEffectContext) -> void:
		var alive: Array[int] = []
		for piece: PieceState in context.material: alive.append(piece.piece_id)
		checkpoints.append({"alive": alive, "score": run.state.ledger.total, "held": run.abilities._held_blasts.size()})
	var outer: CompositeEffect = CompositeEffect.new()
	var frozen: CompositeSkillTarget = CompositeSkillTarget.new()
	var dye_target: SkillTarget = SkillTarget.new()
	dye_target.color = 0
	dye_target.piece_ids = [a.piece_id]
	var fuse_target: SkillTarget = SkillTarget.new()
	fuse_target.piece_ids = [q.piece_id]
	if nested:
		var inner: CompositeEffect = CompositeEffect.new()
		inner.children = [dye]
		outer.children = [inner, fuse]
		var inner_target: CompositeSkillTarget = CompositeSkillTarget.new()
		inner_target.leaf_targets = [dye_target]
		frozen.leaf_targets = [inner_target, fuse_target]
	else:
		outer.children = [dye, fuse]
		frozen.leaf_targets = [dye_target, fuse_target]
	var result: SkillApplyResult = SkillApplyResult.new()
	var rng_before: int = run.state.rewards.target_random.state
	assert_eq(AbilityEffectRunner.preflight(run, outer, frozen), "")
	checkpoints.clear() # Pure preflight may inspect fixed leaves; below observes execution checkpoints only.
	assert_eq(AbilityEffectRunner.apply_skill_effect(run, outer, frozen, result), "")
	assert_eq(checkpoints.size(), 1)
	if checkpoints.size() != 1: return
	assert_eq(checkpoints[0].alive, [q.piece_id, r.piece_id], "五连即时移除，后代未执行")
	assert_eq(checkpoints[0].score, 50)
	assert_eq(checkpoints[0].held, 1)
	assert_eq(result.marked_ids, [q.piece_id], "固定Q不能重抽或多选R")
	assert_eq(run.state.rewards.target_random.state, rng_before)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.abilities._held_blasts.size(), 0)
	assert_eq(result.matches.size(), 4, "染色、五连、F爆破、Q爆破")
	if result.matches.size() == 4:
		assert_eq(result.matches[1].cause, &"match")
		assert_eq(result.matches[2].source_id, source.piece_id)
		assert_eq(result.matches[3].source_id, q.piece_id)
	assert_eq(run.state.ledger.total, 50)
	fuse.observe = Callable()

func test_b01_match_commits_before_fixed_fuse_and_descendants_wait() -> void:
	_boundary(false)

func test_b02_inner_return_does_not_release_descendants() -> void:
	_boundary(true)

func test_nested_dynamic_leaves_sample_once_when_each_is_reached() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	var first: DynamicProbe = DynamicProbe.new()
	var second: DynamicProbe = DynamicProbe.new()
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [first, second]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [RefillCountEffect.new(), inner]
	var frozen: CompositeSkillTarget = CompositeSkillTarget.new()
	var inner_target: CompositeSkillTarget = CompositeSkillTarget.new()
	inner_target.leaf_targets = [SkillTarget.new(), SkillTarget.new()]
	frozen.leaf_targets = [outer.children[0].freeze(SkillRules.effect_context(run.state), null), inner_target]
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.state = run.state.rewards.target_random.state
	random.randi()
	random.randi()
	assert_eq(AbilityEffectRunner.apply_skill_effect(run, outer, frozen, SkillApplyResult.new()), "")
	assert_eq(first.samples, 1)
	assert_eq(second.samples, 1)
	assert_eq(run.state.rewards.target_random.state, random.state)

func test_later_leaf_error_keeps_match_commit_but_cancels_waiting_descendants() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 2), 0)
	var source: PieceState = run.state.rules.state.get_piece_at(Vector2i(2, 2))
	assert_true(run.abilities.assign_fuse(source.piece_id))
	var a: PieceState = run.state.rules.place_piece(Vector2i(4, 2), 1)
	var survivor: PieceState = run.state.rules.place_piece(Vector2i(2, 3), 2)
	var effect: CompositeEffect = CompositeEffect.new()
	effect.children = [DyeMaterialEffect.new(), FailingLeaf.new()]
	var skill: SkillDefinition = SkillDefinition.new()
	skill.skill_id = &"boundary_failure_fixture"
	var ability: AbilityDefinition = AbilityDefinition.new()
	ability.ability_id = &"boundary_acquire"
	ability.event_type = &"skill_acquired"
	ability.effect = effect
	var level: SkillLevelDefinition = SkillLevelDefinition.new()
	level.level = 1
	level.abilities = [ability]
	skill.levels = [level]
	skill.maximum_level = 1
	var target: SkillTarget = SkillTarget.new()
	target.color = 0
	target.piece_ids = [a.piece_id]
	var frozen: CompositeSkillTarget = CompositeSkillTarget.new()
	frozen.leaf_targets = [target, SkillTarget.new()]
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = frozen
	run.state.rewards.active_offer = offer
	run.state.pending_rewards = 1
	run.enter_rewards()
	var result: SkillApplyResult = SkillRules.apply(run, 1, skill.skill_id)
	assert_false(result.success)
	assert_eq(result.error, "injected_post_leaf_failure")
	assert_eq(run.state.phase, RunState.Phase.ERROR)
	assert_eq(run.state.ledger.total, 50)
	assert_not_null(run.state.rules.state.get_piece(survivor.piece_id))
	assert_eq(run.abilities._held_blasts.size(), 0)
	assert_eq(run.abilities._held_matches.size(), 0)
	assert_eq(run.state.rewards.consumed_count, 0)
	assert_eq(run.state.pending_rewards, 1)
	assert_false(SkillRules.apply(run, 1, skill.skill_id).success)
	assert_true(run.abilities.flush_held_blasts().is_empty())

func test_deferred_match_plant_keeps_trigger_time_eligibility() -> void:
	for owned: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
		for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 2), 0)
		var q: PieceState = run.state.rules.place_piece(Vector2i(2, 3), 1)
		if owned: run.state.explosion.upgrades[&"fuse_match_plant"] = 1
		var matches: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches(), true)
		assert_eq(matches.size(), 1)
		assert_false(run.state.explosion.instances.has(q.piece_id), "附引信后代也须等根组合结束")
		run.state.explosion.upgrades[&"fuse_match_plant"] = 0 if owned else 1
		run.abilities.flush_held_blasts()
		assert_eq(run.state.explosion.instances.has(q.piece_id), owned)
