extends GutTest

const Fixture: Script = preload("res://tests/support/composite_contract_fixture.gd")

func _run(materials: int, budget: int) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	run.abilities.config = run.abilities.config.duplicate() as ExplosionConfig
	run.abilities.config.event_budget = budget
	for index: int in range(materials): run.state.rules.place_piece(Vector2i(index * 2, 0), index % 3)
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func _effect(atomic: bool, core: bool, reselect: bool) -> TransformMaterialEffect:
	var effect: TransformMaterialEffect = AtomicTransformEffect.new() if atomic else TransformMaterialEffect.new()
	effect.content_id = &"special_demolition" if core else LineClearState.CONTENT_ROW
	if reselect: effect.reselect_after_previous = true
	else: effect.target_policy = ChoiceEffect.TargetPolicy.DYNAMIC
	return effect

func test_known_dynamic_source_capacity_rejects_before_action_or_random_commit() -> void:
	for atomic: bool in [false, true]:
		for core: bool in [false, true]:
			for reselect: bool in [false, true]:
				var run: RunController = _run(4, 1)
				var current: SkillOffer = Fixture.offer(run, _effect(atomic, core, reselect))
				assert_not_null(current)
				if current == null: continue
				var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
				var result: SkillApplyResult = Fixture.apply(run, current)
				assert_false(result.success)
				assert_eq(result.outcome, &"rejected")
				assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_partial_ordinary_conversion_counts_actual_available_sources() -> void:
	for count: int in [1, 2]:
		for core: bool in [false, true]:
			for reselect: bool in [false, true]:
				var run: RunController = _run(count, count + 1)
				var current: SkillOffer = Fixture.offer(run, _effect(false, core, reselect))
				assert_not_null(current)
				if current == null: continue
				var result: SkillApplyResult = Fixture.apply(run, current)
				assert_true(result.success, result.error)
				assert_eq(result.transformed.size(), count)
				assert_eq(run.state.rewards.consumed_count, 1)

func test_dynamic_atomic_valid_cost_and_exact_source_budget_commit_once() -> void:
	for core: bool in [false, true]:
		var run: RunController = _run(4, 4)
		var current: SkillOffer = Fixture.offer(run, _effect(true, core, false))
		assert_not_null(current)
		if current == null: continue
		var result: SkillApplyResult = Fixture.apply(run, current)
		assert_true(result.success, result.error)
		assert_eq(result.transformed.size(), 3)
		assert_eq(result.removed.size(), 1)
		assert_eq(run.state.rewards.consumed_count, 1)
