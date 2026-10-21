extends GutTest

const FIXTURE: Script = preload("res://tests/support/shape_unlock_fixture.gd")
const CONTRACT: Script = preload("res://tests/support/composite_contract_fixture.gd")

class ObservedFuse extends AssignFuseEffect:
	var id: int
	var observe: Callable
	func _init() -> void:
		target_policy = TargetPolicy.FIXED
	func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
		var target: SkillTarget = SkillTarget.new()
		target.piece_ids = [id]
		return target
	func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
		observe.call()
		return super.build(context, target)

class PlaceCore extends ChoiceEffect:
	func rejection(_context: ChoiceEffectContext) -> String:
		return ""
	func build(_context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		request.kind = ChoiceEffectRequest.Kind.UNLOCK_CORE
		request.coordinate = Vector2i(8, 8)
		request.color = 1
		return request

func test_nested_unlock_commits_match_before_later_leaf_and_holds_all_descendants() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, ShapeUnlockDemo.PROFILE)
	run.initialize("fixture_shape_unlock_chain")
	run.abilities.config = run.abilities.config.duplicate(true) as ExplosionConfig
	run.abilities.config.reward_per_target = 0
	run.abilities.config.bonus_per_blast = 0
	var q: int = run.state.rules.state.get_piece_id(Vector2i(0, 3))
	var r: int = run.state.rules.state.get_piece_id(Vector2i(0, 4))
	var observed: Array[Dictionary] = []
	var fuse: ObservedFuse = ObservedFuse.new()
	fuse.id = q
	fuse.observe = func() -> void:
		if not run.state.rules.shape_unlocks.contains(&"l"): return
		observed.append({"score": run.state.ledger.total, "q": run.state.rules.state.get_piece(q) != null, "r": run.state.rules.state.get_piece(r) != null, "held": run.abilities._held_blasts.size(), "births": run.state.spawn_history.size()})
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [ShapeUnlockDemo.l().choice_effect]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [inner, fuse]
	var offer: SkillOffer = CONTRACT.offer(run, outer)
	var result: SkillApplyResult = CONTRACT.apply(run, offer)
	fuse.observe = Callable()
	assert_true(result.success, result.error)
	assert_eq(observed.size(), 1)
	assert_eq(observed[0], {"score": 50, "q": true, "r": true, "held": 1, "births": 0})
	assert_null(run.state.rules.state.get_piece(q))
	assert_null(run.state.rules.state.get_piece(r))
	assert_eq(result.matches.size(), 3)
	assert_eq(result.matches[0].match_source, &"shape_unlock")
	assert_eq(run.state.spawn_history.size(), 0)
	assert_eq(run.advance().kind, &"recovery")

func test_later_leaf_can_supply_board_and_suppress_recovery() -> void:
	var run: RunController = FIXTURE.run(true)
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [ShapeUnlockDemo.l().choice_effect, PlaceCore.new()]
	var offer: SkillOffer = CONTRACT.offer(run, outer)
	var result: SkillApplyResult = CONTRACT.apply(run, offer)
	assert_true(result.success, result.error)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.spawn_history.size(), 0)
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 0)

func test_duplicate_unlock_inside_root_rejects_before_earlier_leaf_or_random() -> void:
	var run: RunController = FIXTURE.run()
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [ShapeUnlockDemo.l().choice_effect]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [RefillCountEffect.new(), inner, ShapeUnlockDemo.l().choice_effect]
	var offer: SkillOffer = CONTRACT.offer(run, outer)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var result: SkillApplyResult = CONTRACT.apply(run, offer)
	assert_false(result.success)
	assert_eq(result.error, "shape already unlocked")
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_obsolete_unlock_precondition_rejects_before_root_first_leaf() -> void:
	var run: RunController = FIXTURE.run()
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [RefillCountEffect.new(), ShapeUnlockDemo.l().choice_effect]
	var offer: SkillOffer = CONTRACT.offer(run, outer)
	run.state.rules.shape_unlocks.unlock((ShapeUnlockDemo.l().choice_effect as UnlockShapeEffect).template, 99)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var result: SkillApplyResult = CONTRACT.apply(run, offer)
	assert_false(result.success)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_removed_fixed_target_obeys_skip_or_stops_after_committed_unlock() -> void:
	for skip: bool in [true, false]:
		var run: RunController = FIXTURE.run()
		var target: int = run.state.rules.state.get_piece_id(Vector2i.ZERO)
		assert_true(run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i(0, 2))))
		var dye: CONTRACT.FixedDye = CONTRACT.FixedDye.new()
		dye.ids = [target]
		dye.selected = 1
		var outer: CompositeEffect = CompositeEffect.new()
		outer.children = [ShapeUnlockDemo.l().choice_effect, dye]
		outer.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID if skip else CompositeEffect.FixedTargetPolicy.REJECT
		var offer: SkillOffer = CONTRACT.offer(run, outer)
		var result: SkillApplyResult = CONTRACT.apply(run, offer)
		assert_eq(result.success, skip)
		assert_true(run.state.rules.shape_unlocks.contains(&"l"))
		assert_eq(run.state.ledger.total, 50)
		assert_null(run.state.rules.state.get_piece(target))
		assert_eq(run.abilities._held_blasts.size(), 0)
		if skip:
			assert_eq(result.target_changes.size(), 1)
			assert_eq(result.target_changes[0].outcome, "empty")
			assert_eq(run.state.rewards.consumed_count, 1)
		else:
			assert_eq(run.state.phase, RunState.Phase.ERROR)
			assert_eq(run.state.rewards.consumed_count, 0)
			assert_eq(run.advance().kind, &"error")

func test_dynamic_leaf_selects_only_survivors_after_unlock() -> void:
	var run: RunController = FIXTURE.run()
	var survivor: int = run.state.rules.state.get_piece_id(Vector2i(8, 8))
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [ShapeUnlockDemo.l().choice_effect, AssignFuseEffect.new()]
	var offer: SkillOffer = CONTRACT.offer(run, outer)
	var target: CompositeSkillTarget = offer.targets[offer.choices[0].skill_id] as CompositeSkillTarget
	assert_true(target.leaf_targets[1].deferred)
	assert_true(target.leaf_targets[1].piece_ids.is_empty())
	var result: SkillApplyResult = CONTRACT.apply(run, offer)
	assert_true(result.success, result.error)
	assert_eq(result.marked_ids, [survivor])
	assert_true(run.state.explosion.instances.has(survivor))
	assert_eq(run.advance().kind, &"input")
