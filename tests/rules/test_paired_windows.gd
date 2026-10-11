extends GutTest

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)

func _prefix() -> Array[Dictionary]:
	var script: Script = load("res://tools/bot_testing/paired_job.gd") as Script
	return script.fixture_prefix(23)

func test_prefix_restores_all_rng_offer_plan_and_isolates_instances() -> void:
	var prefix: Array[Dictionary] = _prefix()
	assert_false(prefix.is_empty())
	var first: RuleReplay = RuleReplay.new()
	var second: RuleReplay = RuleReplay.new()
	assert_true(first.restore_prefix(prefix), first.error)
	assert_true(second.restore_prefix(prefix), second.error)
	assert_eq(RunSnapshot.capture(first.run), prefix.back().state)
	var original: String = RunSnapshot.digest(RunSnapshot.capture(second.run))
	var bot: RuleBot = RandomLegalBot.new(9)
	var id: StringName = first.run.state.rewards.active_offer.choices[0].skill_id
	assert_true(first.run.execute_command(bot.skill_command(first.run, id)).accepted)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(second.run)), original)
	assert_eq(RunSnapshot.digest(prefix.back().state), original)
	assert_false(second.replay(prefix))
	assert_eq(second.error, "incomplete_record_no_footer")

func test_illegal_intervention_and_partial_prefix_are_rejected() -> void:
	var prefix: Array[Dictionary] = _prefix()
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(prefix), replay.error)
	var id: StringName = replay.run.state.rewards.active_offer.choices[0].skill_id
	var pair: PairedWindow = PairedWindow.new()
	assert_false(pair.compare(prefix, id, id, 20))
	assert_eq(pair.error, "illegal_comparator")
	assert_false(pair.compare(prefix, &"not_in_offer", id, 20))
	var unsafe: Array[Dictionary] = prefix.duplicate(true)
	unsafe.pop_back()
	assert_false(replay.restore_prefix(unsafe))
	var tampered: Array[Dictionary] = prefix.duplicate(true)
	tampered[0].config.rows = "8"
	assert_false(replay.restore_prefix(tampered))

func test_censored_window_has_null_delta_and_includes_immediate_choice() -> void:
	var prefix: Array[Dictionary] = _prefix()
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(prefix), replay.error)
	var choices: Array[SkillDefinition] = replay.run.state.rewards.active_offer.choices
	var pair: PairedWindow = PairedWindow.new()
	assert_true(pair.compare(prefix, choices[0].skill_id, choices[1].skill_id, 20, "random", 17, 0), pair.error)
	assert_false(pair.report.known)
	assert_null(pair.report.delta_score)
	assert_null(pair.report.delta_space)
	assert_eq(pair.report.branches[0].actual_actions, 0)
	for run: RunController in pair.branches:
		var observed: Dictionary = pair.report.branches[pair.branches.find(run)]
		assert_eq(observed.score_delta, run.state.ledger.total - int(prefix.back().state.total))
		assert_eq(observed.space_delta, prefix.back().state.pieces.size() - run.state.rules.state.get_piece_count())
		var verification: RuleReplay = RuleReplay.new()
		assert_true(verification.replay(run.recorder.records), verification.error)
		assert_eq(run.recorder.records.back().reason, "command_limit")

func test_deterministic_branches_replan_and_keep_legal_target_levels() -> void:
	var prefix: Array[Dictionary] = _prefix()
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(prefix), replay.error)
	var choices: Array[SkillDefinition] = replay.run.state.rewards.active_offer.choices
	var first: PairedWindow = PairedWindow.new()
	var second: PairedWindow = PairedWindow.new()
	assert_true(first.compare(prefix, choices[0].skill_id, choices[1].skill_id, 20, "random", 11), first.error)
	assert_true(second.compare(prefix, choices[0].skill_id, choices[1].skill_id, 20, "random", 11), second.error)
	assert_eq(first.report, second.report)
	assert_true(first.report.known)
	assert_null(first.report.target_trigger_count)
	assert_eq(first.branches[0].state.rewards.acquired.get(choices[0].skill_id, 0), first.report.level)
	assert_eq(first.branches[1].state.rewards.acquired.get(choices[0].skill_id, 0), first.report.level_before)
	for run: RunController in first.branches:
		var verification: RuleReplay = RuleReplay.new()
		assert_true(verification.replay(run.recorder.records), verification.error)
		for row: Dictionary in run.recorder.records:
			if row.kind == "CommandAttempt": assert_true(row.accepted)
	for result: Dictionary in first.report.branches:
		assert_true(result.actual_actions == 20 or result.status == "completed")

func test_pressure_report_does_not_classify_tool_limit_as_stage_failure() -> void:
	var strategy: RuleBot = RandomLegalBot.new(7)
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 1
	var runner: BotRunner = BotRunner.new()
	runner.stage_config = preload("res://gameplay/progression/stages/stage_config.tres")
	runner.telemetry_factory = TelemetryFactory.new()
	runner.telemetry_factory.sink_factory = func(_id: String) -> TelemetrySink: return MemorySink.new()
	var recorder: RunRecorder = runner.play(7, 99, strategy, false)
	var report: PressureBatchReport = PressureBatchReport.new()
	report.add(recorder, runner.last_telemetry, "")
	var group: Dictionary = report.groups.values()[0]
	assert_eq(group.stages["1"].reached, 1)
	assert_eq(group.stages["1"].censored, 1)
	assert_eq(group.stages["1"].board_full_unmet, 0)

func test_long_disk_run_flushes_without_a_ui_driver() -> void:
	var strategy: RuleBot = GreedyBot.new()
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 80
	var runner: BotRunner = BotRunner.new()
	runner.telemetry_factory = TelemetryFactory.new()
	var directory: String = "res://.godot/paired-flush-test-" + str(Time.get_ticks_usec())
	runner.telemetry_factory.directory = directory.path_join("telemetry")
	runner.telemetry_factory.record_directory = directory.path_join("records")
	var recorder: RunRecorder = runner.play(1006, 101006, strategy, true, false)
	assert_eq(recorder.error, "")
	assert_eq(runner.last_telemetry.error, "")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(recorder.path), replay.error)
	assert_gt(recorder.flush_count, 2)
