extends GutTest

const Fixture: Script = preload("res://tests/support/composite_contract_fixture.gd")

func test_t06_all_empty_requires_root_permission_and_consumes_once() -> void:
	for allowed: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
		run.state.pending_rewards = 1
		run.enter_rewards()
		var first: DyeMaterialEffect = DyeMaterialEffect.new()
		first.allow_empty_targets = true
		var second: DyeMaterialEffect = DyeMaterialEffect.new()
		second.allow_empty_targets = true
		var effect: CompositeEffect = CompositeEffect.new()
		effect.children = [first, second]
		effect.allow_empty_acquisition = allowed
		run.abilities.config = run.abilities.config.duplicate() as ExplosionConfig
		run.abilities.config.event_budget = 0
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var current: SkillOffer = Fixture.offer(run, effect)
		if not allowed:
			assert_null(current)
			assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
			continue
		assert_not_null(current)
		if current == null: continue
		var cursor: int = run.state.rewards.target_random.state
		var result: SkillApplyResult = Fixture.apply(run, current)
		assert_true(result.success, result.error)
		assert_eq(result.target_changes.size(), 2)
		assert_eq(result.completed_leaves, ["0", "1"])
		assert_eq(run.state.rewards.consumed_count, 1)
		assert_eq(run.state.pending_rewards, 0)
		assert_eq(run.state.rewards.target_random.state, cursor)
		assert_false(Fixture.apply(run, current).success)
		assert_eq(run.state.rewards.consumed_count, 1)

func test_b06_t07_nested_partial_or_error_preserves_commit_and_cancels_only_on_error() -> void:
	for fail: bool in [false, true]:
		var run: RunController = Fixture.run()
		var first: ChoiceEffect = Fixture.first(run)
		var a: int = run.state.rules.state.get_piece_at(Vector2i(5, 2)).piece_id
		var second: Fixture.FixedDye = Fixture.FixedDye.new()
		second.ids = [a]
		second.selected = 1
		var inner: CompositeEffect = CompositeEffect.new()
		inner.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
		inner.children = [second]
		var effect: CompositeEffect = CompositeEffect.new()
		effect.children = [first, inner]
		if fail: effect.children.append(Fixture.FailAfterMatch.new())
		var current: SkillOffer = Fixture.offer(run, effect)
		assert_not_null(current)
		if current == null: continue
		var result: SkillApplyResult = Fixture.apply(run, current)
		assert_eq(result.success, not fail)
		assert_eq(run.state.ledger.total, 50)
		assert_eq(result.completed_leaves, ["0", "1.0"])
		assert_null(run.state.rules.state.get_piece(a))
		assert_eq(result.failed_leaf, "2" if fail else "")
		assert_eq(run.state.rewards.consumed_count, 0 if fail else 1)
		assert_eq(run.state.rules.state.get_piece_at(Vector2i(3, 3)) == null, not fail)
		assert_not_null(run.state.rules.state.get_piece_at(Vector2i(8, 8)))
		assert_true(run.abilities.flush_held_blasts().is_empty())

func test_t08_atomic_cost_and_exact_targets_reject_without_spending_then_commit_once() -> void:
	for invalidate_cost: bool in [false, true]:
		var run: RunController = Fixture.run()
		var effect: AtomicTransformEffect = AtomicTransformEffect.new()
		effect.content_id = LineClearState.CONTENT_ROW
		var current: SkillOffer = Fixture.offer(run, effect)
		assert_not_null(current)
		if current == null: continue
		var target: SkillTarget = current.targets[current.choices[0].skill_id]
		assert_eq(target.cost_piece_ids.size(), 1)
		assert_eq(target.piece_ids.size(), 3)
		if invalidate_cost: run.state.rules.remove_piece(target.cost_piece_ids[0])
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var result: SkillApplyResult = Fixture.apply(run, current)
		if invalidate_cost:
			assert_false(result.success)
			assert_eq(result.outcome, &"rejected")
			assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
		else:
			assert_true(result.success, result.error)
			assert_eq(result.removed.size(), 1)
			assert_eq(result.transformed.size(), 3)
			assert_eq(run.state.line_clear.instances.size(), 3)
			assert_eq(run.state.ledger.total, 0)
			assert_false(Fixture.apply(run, current).success)
			assert_eq(run.state.line_clear.instances.size(), 3)

func test_nested_color_input_is_forwarded_to_inner_leaf() -> void:
	var run: RunController = Fixture.run()
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [ClearMaterialEffect.new()]
	var effect: CompositeEffect = CompositeEffect.new()
	effect.children = [RefillCountEffect.new(), inner]
	var current: SkillOffer = Fixture.offer(run, effect)
	assert_not_null(current)
	if current == null: return
	var result: SkillApplyResult = Fixture.apply(run, current, 1)
	assert_true(result.success, result.error)
	assert_eq(result.completed_leaves, ["0", "1.0"])

func test_t08_incomplete_targets_and_cost_overlap_never_spend() -> void:
	for overlap: bool in [false, true]:
		var run: RunController = Fixture.run()
		var effect: AtomicTransformEffect = AtomicTransformEffect.new()
		effect.content_id = LineClearState.CONTENT_COLUMN
		var current: SkillOffer = Fixture.offer(run, effect)
		assert_not_null(current)
		if current == null: continue
		var target: SkillTarget = current.targets[current.choices[0].skill_id]
		if overlap: target.cost_piece_ids = [target.piece_ids[0]]
		else: run.state.rules.remove_piece(target.piece_ids[0])
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var result: SkillApplyResult = Fixture.apply(run, current)
		assert_false(result.success)
		assert_eq(result.outcome, &"rejected")
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
		assert_eq(run.state.line_clear.instances.size(), 0)

func test_b08_nested_root_runs_once_and_finite_descendants_settle_once() -> void:
	var run: RunController = Fixture.run()
	var q: PieceState = run.state.rules.state.get_piece_at(Vector2i(3, 3))
	assert_true(run.abilities.assign_fuse(q.piece_id))
	run.state.rules.remove_piece(run.state.rules.state.get_piece_at(Vector2i(8, 8)).piece_id)
	run.state.rules.place_piece(Vector2i(3, 4), 2)
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [Fixture.first(run)]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [inner]
	var current: SkillOffer = Fixture.offer(run, outer)
	assert_not_null(current)
	if current == null: return
	var result: SkillApplyResult = Fixture.apply(run, current)
	assert_true(result.success, result.error)
	assert_eq(result.completed_leaves, ["0.0"])
	var blasts: int = 0
	var dyes: int = 0
	for entry: MatchResult in result.matches:
		if entry.cause == &"explosion": blasts += 1
		if entry.cause == &"dye": dyes += 1
	assert_eq(blasts, 2)
	assert_eq(dyes, 1)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_true(run.abilities.flush_held_blasts().is_empty())
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	assert_false(Fixture.apply(run, current).success)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_b08_cycle_rejects_and_retired_queue_cannot_reach_new_run() -> void:
	var run: RunController = Fixture.run()
	var cycle: CompositeEffect = CompositeEffect.new()
	cycle.children = [cycle]
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	assert_null(Fixture.offer(run, cycle))
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
	cycle.children.clear()
	var source: PieceState = run.state.rules.state.get_piece_at(Vector2i(3, 2))
	run.abilities.resolve_removal([source], &"skill_clear", true)
	assert_eq(run.abilities._held_blasts.size(), 1)
	var next: RunController = Fixture.run()
	before = RunSnapshot.canonical(RunSnapshot.capture(next))
	run.retire()
	run.retire()
	assert_true(run.abilities.flush_held_blasts().is_empty())
	assert_false(run.state.ability_events.data().active)
	assert_eq(run.advance().kind, &"closed")
	var command: ChooseSkillCommand = ChooseSkillCommand.new()
	assert_eq(run.execute_command(command).reason, "run_closed")
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(next)), before)

func test_t07_nested_failure_reports_exact_leaf_and_committed_prefix() -> void:
	var run: RunController = Fixture.run()
	var first: ChoiceEffect = Fixture.first(run)
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [RefillCountEffect.new(), Fixture.FailAfterMatch.new()]
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [first, inner, DemolitionStatEffect.new()]
	var current: SkillOffer = Fixture.offer(run, outer)
	assert_not_null(current)
	if current == null: return
	var result: SkillApplyResult = Fixture.apply(run, current)
	assert_false(result.success)
	assert_eq(result.failed_leaf, "1.1")
	assert_eq(result.completed_leaves, ["0", "1.0"])
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.explosion.radius_level, 0)
	assert_true(run.abilities.flush_held_blasts().is_empty())

func test_t06_empty_ability_policy_is_independent_from_reward_consumption() -> void:
	for consumes: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
		var source: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 0)
		run.abilities.assign_fuse(source.piece_id)
		var instance: AbilityInstance = run.state.explosion.instances[source.piece_id]
		instance.definition = instance.definition.duplicate(true) as AbilityDefinition
		instance.definition.consume_on_empty = consumes
		run.abilities.resolve_removal([source], &"skill_clear", true)
		var result: Array[MatchResult] = run.abilities.flush_held_blasts()
		assert_eq(result.size(), 1)
		assert_eq(result[0].removed.size(), 0)
		assert_eq(instance.trigger_count, 1 if consumes else 0)
		assert_eq(run.state.rewards.consumed_count, 0)
		assert_eq(run.state.ledger.total, 0)

func test_nested_empty_permission_applies_only_to_root_acquisition() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	run.state.pending_rewards = 1
	run.enter_rewards()
	var dye: DyeMaterialEffect = DyeMaterialEffect.new()
	dye.allow_empty_targets = true
	var inner: CompositeEffect = CompositeEffect.new()
	inner.children = [dye]
	var refill: RefillCountEffect = RefillCountEffect.new()
	var outer: CompositeEffect = CompositeEffect.new()
	outer.children = [refill, inner]
	var current: SkillOffer = Fixture.offer(run, outer)
	assert_not_null(current)
	if current == null: return
	var result: SkillApplyResult = Fixture.apply(run, current)
	assert_true(result.success, result.error)
	assert_eq(result.completed_leaves, ["0", "1.0"])
	assert_eq(run.state.rewards.consumed_count, 1)

func test_fixed_all_empty_after_invalidation_requires_root_permission() -> void:
	for allowed: bool in [false, true]:
		var run: RunController = Fixture.run()
		var dye: Fixture.FixedDye = Fixture.FixedDye.new()
		var id: int = run.state.rules.state.get_piece_at(Vector2i(5, 2)).piece_id
		dye.ids = [id]
		dye.selected = 2
		var effect: CompositeEffect = CompositeEffect.new()
		effect.children = [dye]
		effect.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
		effect.allow_empty_acquisition = allowed
		var current: SkillOffer = Fixture.offer(run, effect)
		assert_not_null(current)
		if current == null: continue
		run.state.rules.remove_piece(id)
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var result: SkillApplyResult = Fixture.apply(run, current)
		assert_eq(result.success, allowed)
		if not allowed: assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_atomic_consumed_material_clears_only_its_dye_mark() -> void:
	var run: RunController = Fixture.run()
	var effect: AtomicTransformEffect = AtomicTransformEffect.new()
	effect.content_id = LineClearState.CONTENT_ROW
	var current: SkillOffer = Fixture.offer(run, effect)
	assert_not_null(current)
	if current == null: return
	var target: SkillTarget = current.targets[current.choices[0].skill_id]
	run.state.dye.marks[target.cost_piece_ids[0]] = 1
	run.state.dye.marks[target.piece_ids[0]] = 1
	assert_true(Fixture.apply(run, current).success)
	assert_false(run.state.dye.marks.has(target.cost_piece_ids[0]))
	assert_true(run.state.dye.marks.has(target.piece_ids[0]))

func test_fixed_dye_nonempty_frozen_color_survives_single_color_board() -> void:
	var run: RunController = Fixture.run()
	var dye: Fixture.FixedDye = Fixture.FixedDye.new()
	var id: int = run.state.rules.state.get_piece_at(Vector2i(5, 2)).piece_id
	dye.ids = [id]
	dye.selected = 0
	dye.allow_empty_targets = true
	var effect: CompositeEffect = CompositeEffect.new()
	effect.children = [dye]
	var current: SkillOffer = Fixture.offer(run, effect)
	assert_not_null(current)
	if current == null: return
	for piece: PieceState in run.state.rules.state.get_snapshot():
		if piece.piece_id != id: run.state.rules.remove_piece(piece.piece_id)
	assert_true(Fixture.apply(run, current).success)
	assert_eq(run.state.rules.state.get_piece(id).match_color, 0)
