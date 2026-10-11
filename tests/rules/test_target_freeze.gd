extends GutTest

func _config() -> StageConfig:
	var config: StageConfig = StageConfig.new()
	config.targets = [100, 150, 200]
	config.pressure_intervals = [4, 4, 4]
	return config

func test_source_and_other_run_cannot_change_frozen_curve_or_hash() -> void:
	var source: StageConfig = _config()
	var a: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1, source)
	var b: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 2, source)
	var frozen: String = RunSnapshot.digest(RunSnapshot.config(a))
	source.targets[1] = 999
	source.pressure_intervals[0] = 1
	source.curve_version = "changed"
	source.reference_profile = "changed"
	b.state.stage.config.targets[1] = 888
	assert_eq(a.state.stage.config.targets, [100, 150, 200])
	assert_eq(a.state.stage.config.pressure_intervals, [4, 4, 4])
	assert_eq(RunSnapshot.digest(RunSnapshot.config(a)), frozen)
	assert_eq(source.targets[1], 999)
	a.state.reset_counters()
	assert_eq(RunSnapshot.digest(RunSnapshot.config(a)), frozen)

func test_burst_keeps_more_carry_without_pricing_up_following_targets() -> void:
	var snapshots: Array[String] = []
	for score: int in [200, 500]:
		var ledger: ScoreLedger = ScoreLedger.new()
		var stage: StageState = StageState.new(_config(), ledger)
		stage.begin_action(1, 0)
		ledger.commit(0, 1.0, score, &"match", 1)
		var result: StageResult = stage.settle(ledger.get_entries(), false, 1)
		assert_eq(result.carry_out, score - 100)
		stage.start_next()
		assert_eq(stage.target(), 150)
		assert_eq(stage.target_total(), 250)
		assert_eq(stage.missing_score(), 50 if score == 200 else 0)
		assert_null(stage.settle(ledger.get_entries(), false, 2), "携分足够仍不能零行动连过关")
		snapshots.append(RunSnapshot.digest(RunSnapshot.resource_fields(stage.config)))
	assert_eq(snapshots[0], snapshots[1])

func test_choice_points_and_extra_choices_do_not_change_frozen_targets() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1, _config())
	var before: String = RunSnapshot.digest(RunSnapshot.config(run))
	run.state.ledger.commit(0, 1.0, 500, &"match", -1)
	run.state.rewards.consumed_count = 20
	run.state.rewards.acquired[&"score_multiplier"] = 3
	assert_eq(run.state.stage.missing_score(), 0)
	assert_eq(run.state.stage.target(), 100)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), before)

func test_curve_provenance_round_trips_and_invalid_reference_is_rejected() -> void:
	var source: StageConfig = _config()
	source.target_policy = "offline_reference"
	source.curve_version = "reference-trial-v1"
	source.reference_profile = "greedy-normal-pool-v1"
	source.reference_dataset_hash = "a".repeat(64)
	source.reference_rule_version = RunSnapshot.RULES_VERSION
	var restored: StageConfig = StageConfig.from_record(RunSnapshot.resource_fields(source))
	assert_not_null(restored)
	assert_eq(RunSnapshot.resource_fields(restored), RunSnapshot.resource_fields(source))
	var fields: Dictionary = RunSnapshot.resource_fields(source)
	fields.reference_dataset_hash = ""
	assert_null(StageConfig.from_record(fields))
	fields.reference_dataset_hash = "g".repeat(64)
	assert_null(StageConfig.from_record(fields))
	fields.reference_dataset_hash = "a".repeat(64)
	fields.targets = ["0", "150", "200"]
	assert_null(StageConfig.from_record(fields))
	fields.erase("curve_version")
	assert_null(StageConfig.from_record(fields))
	source.targets = [9223372036854775807, 1, 1]
	assert_ne(source.validation_error(), "")

func test_curve_fields_are_in_record_header_and_exact_replay() -> void:
	var source: StageConfig = _config()
	var runner: BotRunner = BotRunner.new()
	runner.stage_config = source
	var strategy: RuleBot = RandomLegalBot.new()
	strategy.config = strategy.config.duplicate() as BotConfig
	strategy.config.move_limit = 2
	var recording: RunRecorder = runner.play(17, 17, strategy, false)
	var challenge: Dictionary = recording.records[0].config.challenge
	assert_eq(challenge.targets, ["100", "150", "200"])
	assert_eq(challenge.curve_version, "fixed-8-targets-v1")
	assert_eq(challenge.target_policy, "fixed_fallback")
	source.targets[0] = 1
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(recording.records), replay.error)
	assert_eq(replay.run.state.stage.config.targets, [100, 150, 200])
