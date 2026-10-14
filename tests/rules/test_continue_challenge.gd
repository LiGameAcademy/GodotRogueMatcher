extends GutTest

func _win() -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = [105]
	config.pressure_intervals = [4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	run.initialize("fixture_dye")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	var move: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	move.piece_id = run.state.rules.state.get_piece_id(Vector2i(4, 6))
	move.target = Vector2i(4, 4)
	assert_true(run.execute_command(move).accepted)
	run.advance()
	run.advance()
	assert_eq(run.state.end_reason, &"challenge_completed")
	return run

func _continue(run: RunController) -> CommandResult:
	return run.execute_command(ContinueChallengeCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id))

func test_continue_keeps_board_score_and_build_and_grants_terminal_reward() -> void:
	var run: RunController = _win()
	var board: String = RunSnapshot.canonical(run.state.rules.state.get_snapshot().map(func(p: PieceState) -> Dictionary: return RunSnapshot.piece(p)))
	run.state.explosion.upgrades[&"precision_reward"] = 2
	run.state.rewards.acquired[&"precision_reward"] = 2
	var score: int = run.state.ledger.total
	var moves: int = run.state.valid_moves
	var random: int = run.state.random.state
	var outcome: CommandResult = _continue(run)
	assert_true(outcome.accepted, outcome.reason)
	if not outcome.accepted: return
	assert_false(run.state.is_game_over)
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.explosion.level(&"precision_reward"), 2)
	assert_eq(run.state.rewards.acquired[&"precision_reward"], 2)
	assert_eq(run.state.ledger.total, score)
	assert_eq(run.state.valid_moves, moves)
	assert_eq(run.state.random.state, random)
	assert_eq(RunSnapshot.canonical(run.state.rules.state.get_snapshot().map(func(p: PieceState) -> Dictionary: return RunSnapshot.piece(p))), board)

func _choose(run: RunController) -> void:
	var step: RunStepResult = run.advance()
	assert_eq(step.kind, &"offer")
	var offer: SkillOffer = step.offer
	if offer == null: return
	for skill: SkillDefinition in offer.choices:
		if skill.requires_color_choice(): continue
		var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
		command.offer_id = offer.offer_id
		command.reward_id = offer.reward_id
		command.skill_id = skill.skill_id
		assert_true(run.execute_command(command).accepted)
		return
	fail_test("expected non-color candidate")

func test_reward_enters_extended_stage_and_whole_record_replays() -> void:
	var run: RunController = _win()
	assert_true(_continue(run).accepted)
	_choose(run)
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.stage.index, 1)
	assert_eq(run.state.stage.target_total(), 210)
	assert_eq(run.state.stage.pressure_interval(), 4)
	assert_eq(run.state.stage.used_actions, 0)
	assert_eq(run.state.rewards.consumed_count, 1)
	assert_eq(run.state.next_refill_count(), 3)
	assert_false(StageText.stage_label(run.state.stage).contains("2 / 1"))
	var projection: Dictionary = TelemetryFacts.stage(RunSnapshot.capture(run), RunSnapshot.config(run))
	assert_false(projection.get("invalid", false))
	assert_eq(projection.target_total, 210)
	run.recorder.finish(run, "abandoned", "continued_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)
	assert_true(replay.complete)

func test_command_roundtrip_and_duplicate_grants_reward_once() -> void:
	var run: RunController = _win()
	var command: ContinueChallengeCommand = ContinueChallengeCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	assert_true(CommandCodec.decode(CommandCodec.encode(command)) is ContinueChallengeCommand)
	var outcome: CommandResult = run.execute_command(command)
	assert_true(outcome.accepted)
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var count: int = run.recorder.records.size()
	assert_same(run.execute_command(command), outcome)
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.recorder.records.size(), count)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)
	assert_false(_continue(run).accepted)
	assert_eq(run.state.pending_rewards, 1)

func test_rejects_unfinished_board_full_and_closed_records() -> void:
	for reason: StringName in [&"", &"board_full", &"challenge_completed"]:
		var run: RunController = _win()
		if reason == &"": run.state.is_game_over = false
		elif reason == &"board_full": run.state.end_reason = reason
		else: run.recorder.finish(run, "completed", "challenge_completed")
		assert_false(run.can_continue_challenge())
		assert_false(_continue(run).accepted)
		assert_eq(run.state.pending_rewards, 0)

func test_extra_goals_use_frozen_final_increment_carry_and_one_new_action() -> void:
	var config: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres")
	var ledger: ScoreLedger = ScoreLedger.new()
	var stage: StageState = StageState.new(config, ledger)
	stage.index = 7
	ledger.commit(0, 1.0, 6000)
	stage.begin_action(1, 0)
	assert_eq(stage.settle(ledger.get_entries(), false, 8).reason, &"challenge_completed")
	assert_true(stage.can_continue())
	stage.continue_challenge()
	stage.start_next()
	assert_eq(stage.index, 8)
	assert_eq(stage.target(), 1000)
	assert_eq(stage.target_total(), 4450)
	assert_eq(stage.carry_in, 2550)
	assert_null(stage.settle(ledger.get_entries(), false, 9))
	stage.begin_action(2, ledger.get_entries().size())
	var result: StageResult = stage.settle(ledger.get_entries(), false, 9)
	assert_not_null(result)
	assert_eq(result.reason, &"stage_passed")
	assert_eq(result.reward_id, 9)
	stage.start_next()
	assert_eq(stage.target_total(), 5450)
	stage.used_actions = 100
	assert_eq(stage.base_refill_count(), 5)
	assert_eq(config.targets.size(), 8)

func test_ending_at_victory_writes_one_valid_footer_and_does_not_continue() -> void:
	var run: RunController = _win()
	BoardRunFlow.finalize(run, "result_to_menu")
	BoardRunFlow.finalize(run, "scene_closed")
	var footers: int = 0
	for row: Dictionary in run.recorder.records:
		if row.kind == "Footer": footers += 1
	assert_eq(footers, 1)
	assert_eq(run.recorder.records.back().status, "completed")
	assert_eq(run.recorder.records.back().reason, "challenge_completed")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)

func test_extend_rejects_target_overflow() -> void:
	var config: StageConfig = StageConfig.new()
	config.targets = [9223372036854775807]
	config.pressure_intervals = [4]
	var ledger: ScoreLedger = ScoreLedger.new()
	var stage: StageState = StageState.new(config, ledger)
	ledger.commit(0, 1.0, 9223372036854775807)
	stage.begin_action(1, 0)
	assert_eq(stage.settle(ledger.get_entries(), false, 1).reason, &"challenge_completed")
	assert_false(stage.can_continue())
