extends GutTest

func _config(targets: Array[int], limits: Array[int]) -> StageConfig:
	var config: StageConfig = StageConfig.new()
	config.targets = targets
	config.action_limits = limits
	return config

func _run(targets: Array[int] = [100, 150], limits: Array[int] = [1, 2]) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, _config(targets, limits))
	run.initialize("fixture_dye")
	return run

func _move(run: RunController, source: Vector2i = Vector2i(4, 6), target: Vector2i = Vector2i(4, 4)) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(source)
	command.target = target
	return run.execute_command(command)

func _drain(run: RunController) -> RunStepResult:
	for index: int in range(12):
		var step: RunStepResult = run.advance()
		if step.kind in [&"offer", &"input", &"finished", &"error"]: return step
	fail_test("run did not reach a safe boundary")
	return null

func _choose(run: RunController, skill: SkillDefinition, target: SkillTarget) -> CommandResult:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = target
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = skill.skill_id
	return run.execute_command(command)

func test_last_action_passes_only_after_tail_and_grants_one_reward() -> void:
	var run: RunController = _run()
	assert_true(_move(run).accepted)
	assert_eq(run.state.stage.used_actions, 1)
	assert_eq(run.state.pending_rewards, 0)
	assert_true(run.state.stage.history.is_empty())
	assert_eq(_drain(run).kind, &"offer")
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.stage.action_score, 105)
	assert_eq(run.state.stage.history[0].carry_out, 5)
	assert_eq(run.state.stage.history[0].reason, &"stage_passed")
	run.advance()
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.stage.history.size(), 1)
	assert_eq(run.check_rewards(999999), 0)

func test_last_action_one_point_short_fails_and_rejects_further_input() -> void:
	var run: RunController = _run([106], [1])
	assert_true(_move(run).accepted)
	assert_eq(_drain(run).kind, &"finished")
	assert_eq(run.state.end_reason, &"stage_target_missed")
	assert_eq(run.state.stage.missing_score(), 1)
	assert_eq(run.state.pending_rewards, 0)
	assert_false(_move(run, Vector2i(8, 8), Vector2i(8, 7)).accepted)
	assert_eq(run.state.stage.used_actions, 1)

func test_final_stage_completes_without_card_and_total_is_not_debited() -> void:
	var run: RunController = _run([105], [1])
	assert_true(_move(run).accepted)
	assert_eq(_drain(run).kind, &"finished")
	assert_eq(run.state.end_reason, &"challenge_completed")
	assert_eq(run.state.ledger.total, 105)
	assert_null(run.prepare_offer())

func test_board_full_wins_over_carry_and_actual_refill_finishes_first() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, _config([100], [1]))
	run.state.phase = RunState.Phase.INPUT
	run.state.stage.carry_in = 100
	for y: int in range(9):
		for x: int in range(9):
			if Vector2i(x, y) != Vector2i(4, 4): run.state.rules.place_piece(Vector2i(x, y), (x + y * 2) % 5)
	assert_true(_move(run, Vector2i(3, 4), Vector2i(4, 4)).accepted)
	assert_eq(_drain(run).kind, &"finished")
	assert_eq(run.state.end_reason, &"board_full")
	assert_eq(run.state.rules.state.get_empty_coordinates().size(), 0)
	assert_eq(run.state.stage.history[0].reason, &"board_full")
	assert_eq(run.state.pending_rewards, 0)

func test_carry_cannot_auto_pass_next_stage_and_rewards_do_not_use_actions() -> void:
	var run: RunController = _run([50, 50, 50], [1, 1, 1])
	assert_true(_move(run).accepted)
	_draining_choice(run)
	assert_eq(run.state.stage.index, 1)
	assert_eq(run.state.stage.carry_in, 55)
	assert_eq(run.state.stage.used_actions, 0)
	assert_eq(run.state.stage.history.size(), 1)
	assert_eq(run.state.stage.missing_score(), 0)
	assert_true(_move(run, Vector2i(8, 8), Vector2i(8, 7)).accepted)
	assert_eq(_drain(run).kind, &"offer")
	assert_eq(run.state.stage.history[1].carry_out, 5)
	assert_eq(run.state.stage.history[1].passed_by, &"carry")
	assert_eq(run.state.ledger.total, 105)

func _draining_choice(run: RunController) -> void:
	_draining_offer(run)
	var skill: SkillDefinition = preload("res://gameplay/progression/content/match_extra.tres")
	assert_true(_choose(run, skill, SkillTarget.new()).accepted)
	assert_eq(_drain(run).kind, &"input")

func _draining_offer(run: RunController) -> void:
	assert_eq(_drain(run).kind, &"offer")

func test_instant_choice_match_scores_total_but_not_next_stage_or_carry() -> void:
	var run: RunController = _run([100, 150], [1, 1])
	assert_true(_move(run).accepted)
	_draining_offer(run)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 1)
	var target: SkillTarget = SkillTarget.new()
	target.coordinate = Vector2i(4, 0)
	assert_true(_choose(run, preload("res://gameplay/progression/content/core_drop.tres"), target).accepted)
	assert_eq(run.state.ledger.total, 155)
	assert_eq(run.state.stage.action_score, 105)
	assert_eq(run.state.stage.used_actions, 1)
	assert_eq(_drain(run).kind, &"input")
	assert_eq(run.state.stage.carry_in, 5)
	assert_eq(run.state.stage.action_score, 0)
	assert_eq(run.state.stage.used_actions, 0)

func test_invalid_and_duplicate_commands_preserve_stage_and_random() -> void:
	var run: RunController = _run()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var random_before: int = run.state.random.state
	assert_false(_move(run, Vector2i(4, 6), Vector2i(0, 3)).accepted)
	assert_eq(run.state.stage.used_actions, 0)
	assert_eq(run.state.stage.root_action_id, 0)
	assert_eq(run.state.random.state, random_before)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(4, 6))
	command.target = Vector2i(4, 4)
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	assert_same(run.execute_command(command), result)
	assert_eq(run.state.stage.used_actions, 1)
	assert_ne(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_active_core_counts_one_action_even_with_zero_score() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, _config([100], [1]))
	run.state.phase = RunState.Phase.INPUT
	run.state.explosion.upgrades[&"core_manual_detonation"] = 1
	var piece: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, 1, 0)
	command.piece_id = piece.piece_id
	assert_true(run.execute_command(command).accepted)
	assert_eq(_drain(run).kind, &"finished")
	assert_eq(run.state.stage.used_actions, 1)
	assert_eq(run.state.stage.action_score, 0)
	assert_eq(run.state.rules.state.get_piece_count(), 3)

func test_invalid_config_refuses_before_births_and_state_is_owned() -> void:
	var config: StageConfig = _config([100], [0])
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	var random_before: int = run.state.random.state
	run.initialize()
	assert_eq(run.state.phase, RunState.Phase.ERROR)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.state.random.state, random_before)
	var a: RunController = _run()
	var b: RunController = _run()
	_move(a)
	assert_eq(b.state.stage.used_actions, 0)
	assert_eq(a.state.stage.config.action_limits, [1, 2])

func test_exact_replay_and_terminal_classification_for_challenge() -> void:
	for target: int in [105, 106]:
		var run: RunController = _run([target], [1])
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "test", false)
		assert_true(_move(run).accepted)
		_draining_terminal(run)
		run.recorder.finish(run, "completed", String(run.state.end_reason))
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay(run.recorder.records), replay.error)
		assert_eq(replay.run.state.end_reason, run.state.end_reason)
		assert_eq(replay.run.state.stage.history.size(), 1)

func _draining_terminal(run: RunController) -> void:
	assert_eq(_drain(run).kind, &"finished")

func test_bot_challenge_has_budget_failure_and_exact_replay() -> void:
	var runner: BotRunner = BotRunner.new()
	runner.stage_config = _config([100000], [2])
	var records: RunRecorder = runner.play(7, 99, RandomLegalBot.new(), false)
	assert_eq(runner.last_replay_error, "")
	assert_eq(records.records.back().reason, "stage_target_missed")
	assert_eq(records.records.back().actions, "2")

func test_classic_mode_still_grants_score_rewards_without_stage_budget() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_dye")
	assert_true(_move(run).accepted)
	assert_eq(run.state.mode_id(), &"classic_endless")
	assert_eq(run.state.pending_rewards, 1)
	assert_false(run.state.stage.enabled())

func test_bot_prepares_stage_reward_before_requesting_a_skill_command() -> void:
	var runner: BotRunner = BotRunner.new()
	runner.stage_config = _config([100, 100000], [10, 2])
	var records: RunRecorder = runner.play(2, 100002, GreedyBot.new(), false)
	assert_eq(runner.last_replay_error, "")
	assert_eq(records.records.back().reason, "stage_target_missed")
	assert_eq(records.records.back().choices, "1")
	assert_eq(records.records.back().actions, "12")
	var analysis: RunAnalysis = RunAnalysis.new()
	analysis.add(records.records)
	assert_eq(analysis.runs[0].mode_id, "stage_challenge")
