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

func _pressure(run: RunController) -> Dictionary:
	var occupied: Array[Vector2i] = []
	for piece: PieceState in run.state.rules.state.get_snapshot(): occupied.append(piece.coordinate)
	return BoardPressure.evaluate(9, 9, occupied, SkillOfferGenerator.CONFIG.occupancy_weight)

func test_pressure_remains_a_diagnostic_with_occupancy_and_fragmentation() -> void:
	assert_eq(BoardPressure.evaluate(3, 3, [], 0.7).P, 0.0)
	var full: Array[Vector2i] = []
	for x: int in range(3):
		for y: int in range(3): full.append(Vector2i(x, y))
	assert_eq(BoardPressure.evaluate(3, 3, full, 0.7).P, 100.0)
	var low: Dictionary = _pressure(_run(false))
	var high: Dictionary = _pressure(_run(true))
	assert_eq(low.n, high.n)
	assert_eq(low.L, 9)
	assert_eq(high.L, 1)
	assert_gt(high.P, low.P)
	assert_eq(BoardPressure.evaluate(3, 3, [], NAN), {})

func test_high_pressure_does_not_waive_hard_gate_or_raise_trial_weight() -> void:
	var high: RunController = _run(true)
	var low: RunController = _run(false)
	var skill: SkillDefinition = _skill(&"instant_color_clear")
	assert_eq(SkillRules.rejection(high.state, skill, high.abilities.config), "尚未进入候选阶段")
	assert_eq(SkillRules.rejection(low.state, skill, low.abilities.config), "尚未进入候选阶段")
	high.state.rewards.consumed_count = 3
	low.state.rewards.consumed_count = 3
	assert_eq(SkillOfferGenerator.weight(high.state, skill), SkillOfferGenerator.weight(low.state, skill))
	var restricted: SkillDefinition = skill.duplicate(true) as SkillDefinition
	restricted.offer_traits.needs = [&"core_supply"]
	assert_eq(SkillRules.rejection(high.state, restricted, high.abilities.config), "missing_required_capability:core_supply")
	restricted.offer_traits.needs.clear()
	restricted.prerequisite = &"missing"
	assert_eq(SkillRules.rejection(high.state, restricted, high.abilities.config), "缺少前置升级")

func test_classic_and_challenge_share_formula_without_startup_or_history_factors() -> void:
	var challenge: RunController = _run(true)
	var classic: RunController = _run(true, false)
	var a: SkillOffer = SkillOfferGenerator.new().generate(challenge)
	var b: SkillOffer = SkillOfferGenerator.new().generate(classic)
	assert_eq(a.rules_version, b.rules_version)
	for id: StringName in a.explanations:
		if a.explanations[id].H == 1 and b.explanations[id].H == 1:
			assert_eq(a.weights[id], b.weights[id])
	assert_false(a.parameter_snapshot.situational_enabled)
	assert_false(a.parameter_snapshot.history_enabled)
	assert_false(a.parameter_snapshot.startup_guarantee)
	assert_false(a.parameter_snapshot.rescue_early_opening)

func test_offer_diagnostic_and_explanations_freeze_until_next_successful_choice() -> void:
	var run: RunController = _run(true)
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var first: SkillOffer = generator.generate(run)
	var frozen: String = RunSnapshot.digest(RunSnapshot.offer_data(first))
	var random: Dictionary = run.state.random_streams.data()
	for piece: PieceState in run.state.rules.state.get_snapshot(): run.state.rules.remove_piece(piece.piece_id)
	assert_same(generator.generate(run), first)
	assert_eq(RunSnapshot.digest(RunSnapshot.offer_data(first)), frozen)
	assert_eq(run.state.random_streams.data(), random)
	run.state.rewards.active_offer = null
	run.state.rewards.consumed_count += 1
	var second: SkillOffer = generator.generate(run)
	assert_eq(second.pressure_snapshot.P, 0.0)
	assert_eq(second.rescue_multiplier, 1.0)

func test_finished_run_and_invalid_trial_config_never_advance_random_or_identity() -> void:
	var run: RunController = _run(true)
	run.state.is_game_over = true
	assert_null(SkillOfferGenerator.new().generate(run))
	run.state.is_game_over = false
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.config = SkillOfferGenerator.CONFIG.duplicate(true) as OfferConfig
	generator.config.factor_max = NAN
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	assert_null(generator.generate(run))
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
	generator.config.factor_max = 2.0
	generator.config.occupancy_weight = 1.1
	assert_false(generator.config.validation_error().is_empty())

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
			if skill.counts_as_utility_pick(): utility += 1
		assert_lte(utility, 1)

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()

func test_offer_record_emits_explanations_actual_slot_denominators_and_neutral_pressure() -> void:
	var run: RunController = _run(true)
	run.recorder = RunRecorder.new()
	var telemetry: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "unified-offer-test")
	run.recorder.record_appended.connect(telemetry.observe_record)
	run.recorder.begin(run, "test", false)
	var before: int = run.state.random.state
	var offer: SkillOffer = run.prepare_offer()
	var seen: bool = false
	for event: Dictionary in telemetry.events:
		if event.event_name == "run_started": assert_false(event.payload.capabilities.rescue_weights)
		if event.event_name == "offer_generated":
			seen = true
			assert_eq(event.payload.P_offer, RunSnapshot.normalize(offer.pressure_snapshot))
			assert_eq(event.payload.explanations, RunSnapshot.normalize(offer.explanations))
			assert_eq(event.payload.slots, RunSnapshot.normalize(offer.slot_log))
			assert_eq(event.payload.offer_rules_version, SkillOfferGenerator.CONFIG.rules_version)
	assert_true(seen)
	assert_eq(run.state.random.state, before)
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
