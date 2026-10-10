extends GutTest

func _run(high: bool = false, challenge: bool = true) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 37, StageConfig.new() if challenge else null)
	for x: int in range(9):
		for y: int in range(9):
			if high and x % 3 == 0 and y % 3 == 0: continue
			if not high and y == 0: continue
			run.state.rules.place_piece(Vector2i(x, y), (x + y) % 5)
	run.enter_rewards()
	run.state.pending_rewards = 2
	return run

func _skill(id: StringName) -> SkillDefinition:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id == id: return skill
	return null

func test_pressure_empty_full_and_equal_occupancy_fragmentation() -> void:
	assert_eq(BoardPressure.evaluate(3, 3, [], 0.7).P, 0.0)
	var coordinates: Array[Vector2i] = []
	for x: int in range(3):
		for y: int in range(3): coordinates.append(Vector2i(x, y))
	assert_eq(BoardPressure.evaluate(3, 3, coordinates, 0.7).P, 100.0)
	var low: Dictionary = RescueOfferRules.pressure(_run(false).state)
	var high: Dictionary = RescueOfferRules.pressure(_run(true).state)
	assert_eq(low.n, high.n)
	assert_eq(low.L, 9)
	assert_eq(high.L, 1)
	assert_gt(high.P, low.P)
	assert_eq(BoardPressure.evaluate(3, 3, [], NAN), {})

func test_rescue_factor_is_bounded_monotonic_and_neutral_for_other_skills() -> void:
	var run: RunController = _run()
	var rescue: SkillDefinition = _skill(&"instant_color_clear")
	var other: SkillDefinition = _skill(&"score_multiplier")
	var profile: Dictionary[StringName, float] = SkillOfferGenerator.build_profile(run.state)
	var base: float = SkillOfferGenerator.weight(run.state, rescue, profile, 0.0)
	var previous: float = base
	for value: int in range(101):
		var current: float = SkillOfferGenerator.weight(run.state, rescue, profile, float(value))
		assert_gte(current, previous)
		assert_lte(current, base * 2.2)
		assert_eq(SkillOfferGenerator.weight(run.state, other, profile, float(value)), SkillOfferGenerator.weight(run.state, other, profile, 0.0))
		previous = current
	assert_almost_eq(previous, base * 2.2, 0.000001)

func test_high_pressure_waives_only_rescue_reward_gate() -> void:
	var high: RunController = _run(true)
	var low: RunController = _run(false)
	var skill: SkillDefinition = _skill(&"instant_color_clear")
	assert_eq(SkillRules.rejection(high.state, skill, high.abilities.config), "")
	assert_eq(SkillRules.rejection(low.state, skill, low.abilities.config), "尚未进入候选阶段")
	var config: SkillDefinition = skill.duplicate() as SkillDefinition
	config.requires_core = true
	assert_eq(SkillRules.rejection(high.state, config, high.abilities.config), "需先获得爆壳手登场")
	config.requires_core = false
	config.prerequisite = &"missing"
	assert_eq(SkillRules.rejection(high.state, config, high.abilities.config), "缺少前置升级")
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var offer: SkillOffer = generator.generate(high)
	assert_true(offer.weights.has(skill.skill_id), "进入正常池而非只跳过rejection")
	var empty: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, StageConfig.new())
	assert_ne(SkillRules.rejection(empty.state, skill, empty.abilities.config, 100.0), "")

func test_classic_keeps_original_weight_gate_and_version() -> void:
	var run: RunController = _run(true, false)
	var skill: SkillDefinition = _skill(&"instant_color_clear")
	assert_eq(RescueOfferRules.factor(run.state, skill, 100.0), 1.0)
	assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "尚未进入候选阶段")
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var offer: SkillOffer = generator.generate(run)
	assert_eq(offer.pressure_snapshot, {})
	assert_eq(offer.rules_version, SkillOfferGenerator.CONFIG.rules_version)

func test_offer_pressure_and_weights_freeze_and_next_group_resamples() -> void:
	var run: RunController = _run(true)
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var first: SkillOffer = generator.generate(run)
	var frozen: String = RunSnapshot.digest(RunSnapshot.offer_data(first))
	var candidate: int = run.state.rewards.candidate_random.state
	for piece: PieceState in run.state.rules.state.get_snapshot(): run.state.rules.remove_piece(piece.piece_id)
	assert_same(generator.generate(run), first)
	assert_eq(RunSnapshot.digest(RunSnapshot.offer_data(first)), frozen)
	assert_eq(run.state.rewards.candidate_random.state, candidate)
	run.state.rewards.active_offer = null
	run.state.rewards.consumed_count += 1
	var second: SkillOffer = generator.generate(run)
	assert_eq(second.pressure_snapshot.P, 0.0)
	assert_eq(second.rescue_multiplier, 1.0)
	assert_false(second.weights.has(&"instant_color_clear"))

func test_finished_run_cannot_be_rescued_and_invalid_config_is_rejected() -> void:
	var run: RunController = _run(true)
	run.state.is_game_over = true
	assert_null(SkillOfferGenerator.new().generate(run))
	var config: RescueOfferConfig = RescueOfferConfig.new()
	config.pressure_start = 100.0
	assert_false(config.validation_error().is_empty())
	assert_true(is_nan(RescueOfferRules.multiplier(90.0, config)))
	config.pressure_start = 40.0
	config.maximum_gain = -1.0
	assert_false(config.validation_error().is_empty())
	config.maximum_gain = 1.2
	config.occupancy_weight = 1.1
	assert_false(config.validation_error().is_empty())

func test_high_pressure_groups_keep_distinct_legal_choices_and_one_utility() -> void:
	for seed_value: int in range(64):
		var run: RunController = _run(true)
		run.state.rewards.candidate_random.seed = seed_value
		var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
		var utility: int = 0
		var ids: Array[StringName] = []
		for skill: SkillDefinition in offer.choices:
			assert_false(ids.has(skill.skill_id))
			ids.append(skill.skill_id)
			assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "")
			if not skill.is_persistent and skill.action != SkillDefinition.Action.ASSIGN_FUSE: utility += 1
		assert_lte(utility, 1)

func test_telemetry_pressure_matches_candidate_snapshot_and_does_not_touch_board_rng() -> void:
	var run: RunController = _run(true)
	var random: int = run.state.random.state
	var observed: Dictionary = TelemetryFacts.pressure(RunSnapshot.capture(run), 9, 9)
	var pressure: Dictionary = RescueOfferRules.pressure(run.state)
	assert_eq(observed.P, pressure.P)
	assert_eq(observed.L, pressure.L)
	SkillOfferGenerator.new().generate(run)
	assert_eq(run.state.random.state, random)

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()

func test_offer_record_emits_frozen_pressure_weights_and_version() -> void:
	var run: RunController = _run(true)
	run.recorder = RunRecorder.new()
	var telemetry: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "pressure-offer-test")
	run.recorder.record_appended.connect(telemetry.observe_record)
	run.recorder.begin(run, "test", false)
	var offer: SkillOffer = run.prepare_offer()
	var seen: bool = false
	for event: Dictionary in telemetry.events:
		if event.event_name == "run_started": assert_true(event.payload.capabilities.rescue_weights)
		if event.event_name == "offer_generated":
			seen = true
			assert_eq(event.payload.P_offer, RunSnapshot.normalize(offer.pressure_snapshot))
			assert_eq(event.payload.weights, RunSnapshot.normalize(offer.weights))
			assert_eq(float(event.payload.rescue_multiplier), offer.rescue_multiplier)
			assert_eq(event.payload.offer_rules_version, RescueOfferRules.CONFIG.rules_version)
	assert_true(seen)

func test_challenge_record_replays_offers_with_current_config() -> void:
	var config: StageConfig = StageConfig.new()
	config.targets = [50, 150, 5000]
	config.pressure_intervals = [4, 4, 4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1000, config)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	var bot: GreedyBot = GreedyBot.new(101000)
	var offers: int = 0
	for step: int in range(300):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): break
		if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
			run.advance()
			continue
		if run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
			if run.state.rewards.active_offer != null: offers += 1
			var command: RunCommand = bot.choose(run)
			if command != null: run.execute_command(command)
			else: break
		else: run.advance()
		if offers >= 2 and run.state.phase == RunState.Phase.INPUT: break
	assert_gt(offers, 0)
	run.recorder.finish(run, "completed" if run.state.is_game_over else "abandoned", String(run.state.end_reason) if run.state.is_game_over else "test_complete")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)
