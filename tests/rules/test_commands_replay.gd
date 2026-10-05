extends GutTest

func _run(seed_value: int = 7) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	return run

func test_command_rejection_duplicates_and_old_run_do_not_repeat_state() -> void:
	var run: RunController = _run()
	var bot: RandomLegalBot = RandomLegalBot.new(4)
	var command: MovePieceCommand = bot.choose(run) as MovePieceCommand
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), result)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)
	var stale: MovePieceCommand = MovePieceCommand.new("old-run", 2, run.state.action_id)
	stale.piece_id = command.piece_id
	stale.target = Vector2i.ZERO
	assert_eq(run.execute_command(stale).reason, "wrong_run")
	assert_eq(run.state.action_id, 1)
	assert_eq(run.state.valid_moves, 1)

func test_record_replay_preserves_all_safety_checkpoints() -> void:
	var runner: BotRunner = BotRunner.new()
	var strategy: RandomLegalBot = RandomLegalBot.new(7)
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 8
	var recorder: RunRecorder = runner.play(7, 99, strategy, false)
	assert_eq(runner.last_replay_error, "")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(recorder.records), replay.error)
	assert_true(replay.complete)
	assert_eq(replay.checked_records, recorder.records.size())
	assert_eq(replay.run.state.valid_moves, 8)

func test_decimal_integer_codec_preserves_64_bit_and_rejects_bad_values() -> void:
	for value: int in [-9223372036854775807 - 1, 9223372036854775807, 9007199254740993]:
		assert_true(CommandCodec.valid_integer(str(value)))
		assert_eq(str(value).to_int(), value)
	for value: Variant in ["9223372036854775808", "-9223372036854775809", "01", "1.0", 1.0, "1e3"]:
		assert_false(CommandCodec.valid_integer(value))
	var run: RunController = _run(9223372036854775807)
	var state: Dictionary = RunSnapshot.capture(run)
	var parsed: Dictionary = JSON.parse_string(RunSnapshot.canonical(state))
	assert_eq(parsed.random[0].seed, str(run.state.random.seed))
	assert_eq(parsed.random[0].state, str(run.state.random.state))

func test_corrupt_command_configuration_and_truncation_are_detected() -> void:
	var runner: BotRunner = BotRunner.new()
	var strategy: RandomLegalBot = RandomLegalBot.new()
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 2
	var recorder: RunRecorder = runner.play(1, 2, strategy, false)
	var changed: Array[Dictionary] = recorder.records.duplicate(true)
	for row: Dictionary in changed:
		if row.kind == "CommandAttempt":
			row.command.target = ["-1", "-1"]
			break
	var replay: RuleReplay = RuleReplay.new()
	assert_false(replay.replay(changed))
	assert_true(replay.error.contains("seq="))
	changed = recorder.records.duplicate(true)
	changed[0].config.columns = "8"
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "configuration_mismatch")
	changed = recorder.records.duplicate(true)
	changed.pop_back()
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "incomplete_record_no_footer")

func test_random_bot_enumerates_each_legal_pair_and_does_not_touch_game_rng() -> void:
	var run: RunController = _run()
	var before: Dictionary = RunSnapshot.capture(run)
	var bot: RandomLegalBot = RandomLegalBot.new(99)
	var moves: Array[MovePieceCommand] = bot.legal_moves(run)
	var seen: Dictionary[String, bool] = {}
	for move: MovePieceCommand in moves:
		assert_true(run.state.rules.validate_move(move.piece_id, move.target).is_valid())
		var key: String = "%d/%s" % [move.piece_id, move.target]
		assert_false(seen.has(key))
		seen[key] = true
	bot.choose(run)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), RunSnapshot.digest(before))

func test_footer_and_versions_cannot_claim_unearned_completion() -> void:
	var strategy: RandomLegalBot = RandomLegalBot.new()
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 1
	var recorder: RunRecorder = BotRunner.new().play(42, 7, strategy, false)
	var replay: RuleReplay = RuleReplay.new()
	for key: String in ["rules_version", "content_version", "offer_version"]:
		var changed: Array[Dictionary] = recorder.records.duplicate(true)
		changed[0][key] = "tampered"
		assert_false(replay.replay(changed))
		assert_eq(replay.error, "record_version_mismatch")
	var changed: Array[Dictionary] = recorder.records.duplicate(true)
	changed.back().status = "completed"
	changed.back().reason = "board_full"
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "invalid_completed_footer")
	changed = recorder.records.duplicate(true)
	changed.back().status = "rule_error"
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "invalid_rule_error_footer")

func test_write_failure_keeps_gameplay_and_diagnostic_replay() -> void:
	var run: RunController = _run()
	var blocked_path: String = "user://record_directory_is_file"
	var file: FileAccess = FileAccess.open(blocked_path, FileAccess.WRITE)
	file.store_string("test")
	file.close()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", true, "unknown", blocked_path)
	assert_false(run.recorder.error.is_empty())
	assert_true(run.execute_command(RandomLegalBot.new().choose(run)).accepted)
	run.report_error("test_driver_cannot_advance")
	run.recorder.finish(run, "rule_error", run.state.rule_error)
	assert_false(run.recorder.records.back().record_complete)
	# 无写盘错误的同一诊断轨迹能重算，并保留异常分类。
	run = _run()
	run.report_error("test_driver_cannot_advance")
	run.recorder.finish(run, "rule_error", run.state.rule_error)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)

func test_greedy_bot_prefers_reachable_five_without_mutating_live_board() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 0)
	var fifth: PieceState = run.state.rules.place_piece(Vector2i(4, 1), 0)
	run.start_turn()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var move: MovePieceCommand = GreedyBot.new(5).choose(run) as MovePieceCommand
	assert_eq(move.piece_id, fifth.piece_id)
	assert_eq(move.target, Vector2i(4, 0))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_jsonl_file_round_trip_and_reports_match_footer() -> void:
	var runner: BotRunner = BotRunner.new()
	var strategy: RandomLegalBot = RandomLegalBot.new()
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 3
	var recorder: RunRecorder = runner.play(42, 7, strategy)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(recorder.path), replay.error)
	var analysis: RunAnalysis = RunAnalysis.new()
	analysis.add(recorder.records)
	assert_eq(analysis.runs.size(), 1)
	assert_eq(analysis.turns.size(), 3)
	assert_eq(analysis.runs[0].score, recorder.records.back().score)
	assert_true(analysis.write("user://bot_reports/test"), analysis.error)

func test_fixture_explosion_records_replay_without_injecting_results() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", false)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	assert_eq(run.state.ledger.total, 70)
	assert_gt(result.turn.matches.size(), 1)
	while run.state.phase != RunState.Phase.INPUT: run.advance()
	run.recorder.finish(run, "abandoned", "fixture_complete")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)

func test_fixed_seed_rerun_preserves_commands_and_final_state() -> void:
	var strategy: RandomLegalBot = RandomLegalBot.new()
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 5
	var first: RunRecorder = BotRunner.new().play(43, 99, strategy, false)
	var second: RunRecorder = BotRunner.new().play(43, 99, strategy, false)
	var a: Dictionary = first.records.back().final.duplicate(true)
	var b: Dictionary = second.records.back().final.duplicate(true)
	a.erase("run_id")
	b.erase("run_id")
	assert_eq(RunSnapshot.digest(a), RunSnapshot.digest(b))
