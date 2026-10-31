extends GutTest

## Batch trial wiring and replay contracts, not balance or natural-sample acceptance.
func _options(a: String = "0.5", d: String = "0.0") -> OfferTrialOptions:
	return OfferTrialOptions.from_args(PackedStringArray(["--offer-a=" + a, "--offer-d=" + d,
		"--experiment=smoke_contract", "--variant=synthetic_trial"]))

func _run(config: OfferConfig = null) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 42, null, &"", config)

func test_trial_options_require_all_explicit_fields_and_reject_bad_values() -> void:
	assert_null(OfferTrialOptions.from_args(PackedStringArray()).config)
	assert_eq(_options().error, "")
	for args: PackedStringArray in [
		PackedStringArray(["--offer-a=0.5"]),
		PackedStringArray(["--offer-a=NaN", "--offer-d=0.25", "--experiment=x", "--variant=y"]),
		PackedStringArray(["--offer-a=0.25", "--offer-d=0.25", "--experiment=x", "--variant=y", "--offer-a=0"]),
		PackedStringArray(["--offer-a=0.25", "--offer-d=0.25", "--experiment=x\n", "--variant=y"]),
		PackedStringArray(["--offer-unknown=1"]),
		PackedStringArray(["--offer-a", "--offer-d=0.25", "--experiment=x", "--variant=y"]),
	]:
		assert_ne(OfferTrialOptions.from_args(args).error, "", str(args))
	for value: String in ["-0.25", "0.250", "1", "inf", "1e-1"]:
		assert_ne(_options(value).error, "")
	assert_eq(_options("0", "0.25").config.related_gain, 0.0)
	assert_null(_options().metadata().offer_trial.acceptance)
	assert_eq(OfferTrialOptions.from_args(PackedStringArray(["--offer-a=0.5", "--offer-d=0.25", "--experiment=o1-smoke", "--variant=a_0.5"])).error, "")

func test_trial_runs_copy_configuration_without_mutating_other_runs_or_template() -> void:
	var trial: OfferTrialOptions = _options()
	var first: RunController = _run(trial.config)
	var second: RunController = _run(trial.config)
	var normal: RunController = _run()
	trial.config.related_gain = 0.0
	assert_eq(first.offer_configuration().related_gain, 0.5)
	first.offer_configuration().rarity_weights[0] = 3.0
	assert_eq(second.offer_configuration().rarity_weights[0], 1.0)
	assert_eq(SkillOfferGenerator.CONFIG.related_gain, 0.25)
	assert_eq(SkillOfferGenerator.CONFIG.rarity_weights[0], 1.0)
	assert_eq(RunSnapshot.config(normal).offer, RunSnapshot.resource_fields(SkillOfferGenerator.CONFIG))
	assert_ne(RunSnapshot.digest(RunSnapshot.config(second)), RunSnapshot.digest(RunSnapshot.config(normal)))

func test_default_stage_config_keeps_the_archived_v46_full_fingerprint() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1000,
		preload("res://gameplay/progression/stages/stage_config.tres"))
	assert_eq(RunSnapshot.config(run).offer, RunSnapshot.resource_fields(SkillOfferGenerator.CONFIG))
	# Real v46 baseline from docs/evidence/o1-unified-offers/rereview-2026-10-29/bot-runs.csv.
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), "d021abbb7a3069cb7e4e35ba4be18cab987acdd3e53ca5755218ad975f385808")

func test_programmatic_invalid_trial_is_rejected_before_run_creation() -> void:
	var runner: BotRunner = BotRunner.new()
	runner.trial_options = _options()
	runner.trial_options.config.rarity_weights[0] = 3.0
	assert_null(runner.play(42, 100042, GreedyBot.new(42), false))
	assert_eq(runner.last_replay_error, "unsupported offer trial field change")
	assert_null(runner.last_telemetry)

func test_nested_curve_resources_are_isolated_by_run_construction() -> void:
	# Isolation fixture only: the CLI must still refuse changing the registered rarity curve.
	var template: OfferConfig = _options().config
	var step: OfferRarityStep = OfferRarityStep.new()
	step.first_choice = 2
	step.weights = [1.0, 0.65, 0.35, 0.15, 0.06]
	template.rarity_steps = [step]
	var first: RunController = _run(template)
	var second: RunController = _run(template)
	first.offer_configuration().rarity_steps[0].weights[0] = 9.0
	assert_eq(second.offer_configuration().rarity_steps[0].weights[0], 1.0)
	assert_eq(template.rarity_steps[0].weights[0], 1.0)
	assert_true(SkillOfferGenerator.CONFIG.rarity_steps.is_empty())

func test_default_generation_consumes_the_actual_run_trial_configuration() -> void:
	var run: RunController = _run(_options().config)
	run.state.pending_rewards = 1
	run.state.rewards.consumed_count = 4
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.unlocked = true
	var offer: SkillOffer = run.prepare_offer()
	assert_not_null(offer)
	if offer == null: return
	assert_eq(offer.parameter_snapshot.related_gain, 0.5)
	assert_eq(offer.parameter_snapshot.gap_gain, 0.0)
	assert_true(offer.explanations.has(&"blast_extra"))
	var row: Dictionary = offer.explanations.get(&"blast_extra", {})
	if row.is_empty(): return
	assert_eq(row.related, 1)
	assert_eq(row.fills_gap, 1)
	assert_eq(float(row.W), float(row.B) * 1.5)

func _record_trial() -> RunRecorder:
	var runner: BotRunner = BotRunner.new()
	runner.trial_options = _options()
	runner.stage_config = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
	runner.stage_config.targets = [1, 10, 100, 300, 400, 550, 750, 1000]
	var bot: GreedyBot = GreedyBot.new(42)
	bot.config = bot.config.duplicate(true) as BotConfig
	bot.config.move_limit = 8
	var record: RunRecorder = runner.play(42, 100042, bot, false)
	assert_eq(runner.last_replay_error, "")
	return record

func test_trial_record_and_replay_preserve_parameters_config_hash_and_actual_offers() -> void:
	var recorder: RunRecorder = _record_trial()
	assert_not_null(recorder)
	if recorder == null: return
	var header: Dictionary = recorder.records.front()
	assert_eq(header.config.offer.related_gain, 0.5)
	assert_eq(header.config.offer.gap_gain, 0.0)
	assert_eq(header.metadata.experiment_id, "smoke_contract")
	assert_eq(header.metadata.variant_id, "synthetic_trial")
	assert_eq(header.metadata.offer_trial.related_gain, 0.5)
	assert_eq(header.metadata.collection_context, "bot_batch")
	var offers: int = 0
	for row: Dictionary in recorder.records:
		if row.kind == "Offer":
			offers += 1
			assert_eq(row.offer.parameters.related_gain, 0.5)
	assert_gt(offers, 0)
	var replay: RuleReplay = RuleReplay.new()
	var valid: bool = replay.replay(recorder.records)
	assert_true(valid, replay.error)
	if valid: assert_eq(replay.run.offer_configuration().related_gain, 0.5)

func test_replay_refuses_missing_trial_binding_and_other_config_changes_even_with_rehashed_header() -> void:
	var recorder: RunRecorder = _record_trial()
	if recorder == null: return
	var replay: RuleReplay = RuleReplay.new()
	var changed: Array[Dictionary] = recorder.records.duplicate(true)
	changed[0].metadata.erase("offer_trial")
	assert_false(replay.replay(changed))
	changed = recorder.records.duplicate(true)
	changed[0].metadata.offer_trial.related_gain = 0.25
	assert_false(replay.replay(changed))
	changed = recorder.records.duplicate(true)
	changed[0].config.offer.maximum_utility_picks = "0"
	changed[0].config_hash = RunSnapshot.digest(changed[0].config)
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "configuration_mismatch")
	changed = recorder.records.duplicate(true)
	changed[0].source = "human"
	assert_false(replay.replay(changed))
	for value: Variant in [true, "0.5", INF, 0.1]:
		changed = recorder.records.duplicate(true)
		changed[0].config.offer.related_gain = value
		changed[0].metadata.offer_trial.related_gain = value
		changed[0].config_hash = RunSnapshot.digest(changed[0].config)
		assert_false(replay.replay(changed), str(value))

func _checkpoint_run(reward: bool) -> RunController:
	var options: OfferTrialOptions = _options()
	var config: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
	config.targets = [1, 150, 200, 300, 400, 550, 750, 1000]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, config, &"", options.config)
	run.initialize("fixture_f6" if reward else "normal")
	run.recorder = RunRecorder.new()
	run.recorder.metadata = options.metadata()
	run.recorder.begin(run, "bot", false)
	if reward:
		var move: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
		move.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
		move.target = Vector2i(5, 4)
		assert_true(run.execute_command(move).accepted)
		for index: int in range(20):
			if run.state.rewards.active_offer != null: break
			run.advance()
		assert_not_null(run.state.rewards.active_offer)
	return run

func test_input_and_frozen_rewards_preserve_trial_config_and_six_stream_next_values() -> void:
	for reward: bool in [false, true]:
		var run: RunController = _checkpoint_run(reward)
		var encoded: Dictionary = RunCheckpointCodec.encode(run)
		assert_true(encoded.ok, encoded.reason)
		if not encoded.ok: continue
		var restored: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest)
		assert_true(restored.ok, restored.reason)
		if not restored.ok: continue
		assert_eq(RunSnapshot.capture(restored.run), RunSnapshot.capture(run))
		assert_eq(restored.run.offer_configuration().related_gain, 0.5)
		# Re-saving the reconstructed prefix must keep the binding, not silently become a default header.
		var again: Dictionary = RunCheckpointCodec.encode(restored.run)
		assert_true(again.ok, again.reason)
		if again.ok: assert_true(RunCheckpointCodec.decode(again.payload, again.manifest).ok)
		for stream_id: StringName in RunRandomStreams.IDS:
			assert_eq(restored.run.state.random_streams.stream(stream_id).randi(), run.state.random_streams.stream(stream_id).randi())
		var baseline: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, run.state.stage.config)
		assert_false(RunCheckpointCodec.decode(encoded.payload, RunCheckpointCodec.manifest(baseline)).ok)
