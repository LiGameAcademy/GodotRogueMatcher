extends GutTest

const FIXTURE: Script = preload("res://tests/support/shape_unlock_fixture.gd")

func test_real_acquisition_immediately_scans_all_enabled_rules_once() -> void:
	var run: RunController = FIXTURE.run()
	for x: int in range(4, 9): run.state.rules.place_piece(Vector2i(x, 6), 2)
	var before_plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	var random_before: int = run.state.random.state
	var response: CommandResult = FIXTURE.choose(run)
	assert_not_null(response)
	assert_true(response.accepted, response.reason)
	assert_eq(response.skill.matches.size(), 2)
	assert_eq(run.state.ledger.total, 100)
	for result: MatchResult in response.skill.matches: assert_eq(result.match_source, &"shape_unlock")
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_true(run.state.rules.shape_unlocks.contains(&"l"))
	assert_eq(run.state.rewards.acquired.get(&"fixture_unlock_l"), 1)
	assert_eq(run.state.rewards.consumed_count, 1)
	assert_eq(run.state.valid_moves, 0)
	assert_eq(run.state.activations, 0)
	assert_false(run.direct_match())
	assert_eq(run.state.random.state, random_before)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), before_plan)

func test_no_match_is_successful_unlock_and_precision_reward_applies_once() -> void:
	var run: RunController = FIXTURE.run()
	run.state.rules.remove_piece(run.state.rules.state.get_piece_id(Vector2i.ZERO))
	var response: CommandResult = FIXTURE.choose(run)
	assert_true(response.accepted, response.reason)
	assert_true(response.skill.matches.is_empty())
	assert_true(run.state.rules.shape_unlocks.contains(&"l"))
	assert_eq(run.state.ledger.total, 0)
	var rewarded: RunController = FIXTURE.run()
	rewarded.state.explosion.upgrades[&"precision_reward"] = 1
	assert_true(FIXTURE.choose(rewarded).accepted)
	assert_eq(rewarded.state.ledger.total, 55)

func test_duplicate_command_is_idempotent_and_old_run_cannot_unlock_new_run() -> void:
	var run: RunController = FIXTURE.run(true)
	var offer: SkillOffer = run.prepare_offer()
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, 0)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = &"fixture_unlock_l"
	var response: CommandResult = run.execute_command(command)
	assert_true(response.accepted)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), response)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
	assert_eq(run.advance().kind, &"recovery")
	before = RunSnapshot.canonical(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), response)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
	var other: RunController = FIXTURE.run()
	assert_false(other.execute_command(command).accepted)
	assert_false(other.state.rules.shape_unlocks.contains(&"l"))
	run.state.reset_counters()
	assert_false(run.state.rules.shape_unlocks.contains(&"l"))
	assert_false(run.state.rules.shape_unlocks.recovery_pending)

func test_legal_pool_filters_shape_identity_without_raising_other_shape_affinity() -> void:
	var run: RunController = FIXTURE.run()
	var profile: SkillBuildSnapshot = SkillOfferGenerator.build_snapshot(run.state)
	var before: float = SkillOfferGenerator.weight(run.state, ShapeUnlockDemo.t(), profile)
	assert_true(FIXTURE.choose(run).accepted)
	run.state.pending_rewards += 1
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([ShapeUnlockDemo.l(), ShapeUnlockDemo.t()])
	var offer: SkillOffer = generator.generate(run)
	assert_eq(offer.choices.size(), 1)
	assert_eq(offer.choices[0].skill_id, ShapeUnlockDemo.t().skill_id)
	assert_true(SkillOfferGenerator.build_snapshot(run.state).invested.has(&"shape"))
	assert_eq(offer.weights[ShapeUnlockDemo.t().skill_id], before)
	var alias: SkillDefinition = ShapeUnlockDemo.l().duplicate(true) as SkillDefinition
	alias.skill_id = &"another_l_recipe"
	assert_eq(SkillRules.rejection(run.state, alias, run.abilities.config), "shape already unlocked")
	assert_false(SkillOfferGenerator.CATALOG.has(ShapeUnlockDemo.l()))

func test_obsolete_unconsumed_choice_refuses_without_mutation_and_keeps_other_choice() -> void:
	var run: RunController = FIXTURE.run()
	var offer: SkillOffer = run.prepare_offer()
	# Another legitimate unlock leaf commits before this still-unconsumed offer is confirmed.
	var effect: UnlockShapeEffect = ShapeUnlockDemo.l().choice_effect as UnlockShapeEffect
	var result: SkillApplyResult = SkillApplyResult.new()
	assert_eq(AbilityEffectRunner.apply_skill_effect(run, effect, SkillTarget.new(), result), "")
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var random_before: int = run.state.rewards.target_random.state
	var response: CommandResult = FIXTURE.choose(run)
	assert_false(response.accepted)
	assert_eq(response.reason, "shape already unlocked")
	# Attempt identity is recorded, but no rule state, RNG or reward consumption changes.
	var after: Dictionary = RunSnapshot.capture(run)
	var frozen: Dictionary = JSON.parse_string(before)
	after.erase("last_command")
	frozen.erase("last_command")
	assert_eq(RunSnapshot.canonical(after), RunSnapshot.canonical(frozen))
	assert_eq(run.state.rewards.target_random.state, random_before)
	assert_eq(run.state.rewards.active_offer, offer)
	assert_eq(run.state.pending_rewards, 1)
	assert_true(FIXTURE.choose(run, &"fixture_unlock_t").accepted)

func test_unlock_budget_failure_rejects_before_enable_score_or_random() -> void:
	var run: RunController = FIXTURE.run()
	var offer: SkillOffer = run.prepare_offer()
	run.abilities.config = run.abilities.config.duplicate(true) as ExplosionConfig
	run.abilities.config.event_budget = 0
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var response: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"fixture_unlock_l")
	assert_false(response.success)
	assert_true(response.error.contains("budget"))
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_continue_challenge_keeps_shape_and_history_without_rescanning() -> void:
	var config: StageConfig = StageConfig.new()
	config.targets = [50]
	config.pressure_intervals = [3]
	var run: RunController = FIXTURE.run(false, config)
	assert_true(FIXTURE.choose(run).accepted)
	run.advance()
	var move: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	move.piece_id = run.state.rules.state.get_piece_id(Vector2i(8, 8))
	move.target = Vector2i(8, 7)
	assert_true(run.execute_command(move).accepted)
	run.advance()
	assert_eq(run.advance().challenge.reason, &"challenge_completed")
	var total: int = run.state.ledger.total
	var shapes: Array[StringName] = run.state.rules.shape_unlocks.ids()
	var command: ContinueChallengeCommand = ContinueChallengeCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	assert_true(run.execute_command(command).accepted)
	assert_eq(run.state.rules.shape_unlocks.ids(), shapes)
	assert_eq(run.state.ledger.total, total)
	assert_eq(run.state.rewards.acquired.get(&"fixture_unlock_l"), 1)
	assert_false(SkillRules.rejection(run.state, ShapeUnlockDemo.l(), run.abilities.config).is_empty())
