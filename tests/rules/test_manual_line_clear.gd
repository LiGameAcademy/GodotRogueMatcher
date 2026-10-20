extends GutTest

const MANUAL: SkillDefinition = preload("res://gameplay/progression/content/line_manual_clear.tres")

func _run() -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = [10000]
	config.pressure_intervals = [4]
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 74, config)

func _command(run: RunController, piece: PieceState) -> ActivateLineCommand:
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = piece.piece_id
	return command

func _finish_action(run: RunController) -> void:
	for attempt: int in range(5):
		if run.state.phase == RunState.Phase.INPUT or run.state.is_game_over: return
		run.advance()

func _game_digest(run: RunController) -> String:
	var snapshot: Dictionary = RunSnapshot.capture(run)
	# Rejected attempts still consume a command identity, never game state or RNG.
	snapshot.erase("last_command")
	return RunSnapshot.digest(snapshot)

func test_short_sweeps_score_one_two_four_and_five_without_match_bonuses() -> void:
	for count: int in [1, 2, 4, 5]:
		var run: RunController = _run()
		var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i.ZERO, 0)
		for x: int in range(1, count + 1): run.state.rules.place_piece(Vector2i(x, 0), x % 5)
		run.state.explosion.upgrades[&"precision_reward"] = 2
		run.state.explosion.upgrades[&"longline_reward"] = 2
		var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"consume")
		assert_eq(results.size(), 1)
		assert_eq(results[0].score_entry.base_score, count * (count + 5))
		assert_eq(results[0].score_entry.extra_score, 0)
		assert_eq(run.state.ledger.total, count * (count + 5))

func test_short_sweep_applies_global_multiplier_and_extra() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i.ZERO, 0)
	for y: int in [1, 2]: run.state.rules.place_piece(Vector2i(0, y), y)
	run.state.explosion.multiplier_level = 1
	run.state.explosion.match_extra_level = 1
	var result: MatchResult = run.abilities.resolve_removal([source], &"match")[0]
	assert_eq(result.score_entry.base_score, 14)
	assert_almost_eq(result.score_entry.multiplier, 1.2, 0.001)
	assert_eq(result.score_entry.extra_score, 10)
	assert_eq(result.score_entry.final_score, 26)

func test_unlock_card_needs_either_supply_and_uses_shared_acquisition_pipeline() -> void:
	var run: RunController = _run()
	assert_false(SkillRules.rejection(run.state, MANUAL, run.abilities.config).is_empty())
	run.state.line_clear.column_unlocked = true
	assert_eq(SkillRules.rejection(run.state, MANUAL, run.abilities.config), "")
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 1
	offer.choices = [MANUAL]
	offer.targets[MANUAL.skill_id] = SkillRules.freeze_target(run.state, MANUAL)
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, 0)
	command.offer_id = 1
	command.reward_id = 1
	command.skill_id = MANUAL.skill_id
	var config_before: String = RunSnapshot.digest(RunSnapshot.config(run))
	assert_true(run.execute_command(command).accepted)
	assert_eq(run.state.line_clear.level(MANUAL.skill_id), 1)
	assert_eq(run.state.skill_instances[MANUAL.skill_id].level, 1)
	assert_eq(run.state.skill_instances[MANUAL.skill_id].abilities[0].trigger_count, 1)
	assert_eq(SkillRules.rejection(run.state, MANUAL, run.abilities.config), "已满级")
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config_before)
	var other: RunController = _run()
	assert_eq(other.state.line_clear.level(MANUAL.skill_id), 0)

func test_manual_row_and_column_cost_one_action_refill_and_activate_once() -> void:
	for axis: int in [LineClearState.AXIS_ROW, LineClearState.AXIS_COLUMN]:
		var run: RunController = _run()
		run.start_turn()
		run.state.line_clear.upgrades[MANUAL.skill_id] = 1
		var source: PieceState = run.abilities.add_line_piece(axis, Vector2i.ZERO, 0)
		for index: int in [1, 2]:
			run.state.rules.place_piece(Vector2i(index, 0) if axis == 0 else Vector2i(0, index), index)
		var instance: AbilityInstance = run.state.line_clear.instances[source.piece_id]
		var command: ActivateLineCommand = _command(run, source)
		var result: CommandResult = run.execute_command(command)
		assert_true(result.accepted, result.reason)
		assert_eq(result.turn.matches.size(), 1)
		assert_eq(result.turn.matches[0].line_axis, axis)
		assert_eq(run.state.ledger.total, 14)
		assert_eq(run.state.action_id, 1)
		assert_eq(run.state.activations, 1)
		assert_eq(instance.trigger_count, 1)
		assert_eq(run.state.rules.state.get_piece_count(), 0)
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		assert_same(run.execute_command(command), result)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
		_finish_action(run)
		assert_eq(run.state.spawn_history.size(), 3)
		assert_eq(run.state.stage.used_actions, 1)
		assert_eq(run.state.stage.action_score, 14)
		assert_eq(run.state.turn_count, 2)

func test_refill_cost_stays_previewed_when_this_action_increases_pressure() -> void:
	var run: RunController = _run()
	run.state.stage.used_actions = 3
	run.start_turn()
	assert_eq(run.state.next_refill_count(), 3)
	run.state.line_clear.upgrades[MANUAL.skill_id] = 1
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	run.state.rules.place_piece(Vector2i(1, 0), 1)
	assert_true(run.execute_command(_command(run, source)).accepted)
	_finish_action(run)
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.next_refill_count(), 4)

func test_goal_passes_only_after_normal_refill_and_full_action_settlement() -> void:
	var run: RunController = _run()
	run.state.stage.config.targets = [14, 10000]
	run.state.stage.config.pressure_intervals = [4, 4]
	assert_eq(run.state.stage.config.validation_error(), "")
	run.start_turn()
	run.state.line_clear.upgrades[MANUAL.skill_id] = 1
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	for x: int in [1, 2]: run.state.rules.place_piece(Vector2i(x, 0), x)
	assert_true(run.execute_command(_command(run, source)).accepted)
	assert_eq(run.state.ledger.total, 14)
	assert_eq(run.state.pending_rewards, 0)
	assert_eq(run.advance().kind, &"end_turn")
	var step: RunStepResult = run.advance()
	assert_eq(step.kind, &"spawn")
	assert_eq(step.spawns.size(), 3)
	assert_not_null(step.challenge)
	assert_eq(step.challenge.reason, &"stage_passed")
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(ManualActivationRules.remaining(run.state, true), 2)
	run.state.stage.start_next()
	assert_eq(ManualActivationRules.remaining(run.state, true), 2)

func test_empty_sweep_still_consumes_action_and_refills_without_award() -> void:
	var run: RunController = _run()
	run.start_turn()
	run.state.line_clear.upgrades[MANUAL.skill_id] = 1
	run.state.explosion.match_extra_level = 5
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	assert_true(run.execute_command(_command(run, source)).accepted)
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.activations, 1)
	_finish_action(run)
	assert_eq(run.state.spawn_history.size(), 3)

func test_rejections_leave_occupancy_score_and_random_unchanged() -> void:
	var run: RunController = _run()
	run.start_turn()
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	var ordinary: PieceState = run.state.rules.place_piece(Vector2i(1, 0), 1)
	var before: String = _game_digest(run)
	assert_eq(run.execute_command(_command(run, source)).reason, "manual_not_installed")
	assert_eq(_game_digest(run), before)
	run.state.line_clear.upgrades[MANUAL.skill_id] = 1
	before = _game_digest(run)
	assert_eq(run.execute_command(_command(run, ordinary)).reason, "invalid_line_piece")
	assert_eq(_game_digest(run), before)
	run.state.phase = RunState.Phase.REWARDS
	before = _game_digest(run)
	assert_eq(run.execute_command(_command(run, source)).reason, "busy")
	assert_eq(_game_digest(run), before)

func test_budget_rejection_precedes_manual_consumption() -> void:
	var run: RunController = _run()
	run.start_turn()
	run.state.line_clear.upgrades[MANUAL.skill_id] = 1
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities.config = config
	var before: String = _game_digest(run)
	assert_string_contains(run.execute_command(_command(run, source)).reason, "budget")
	assert_eq(_game_digest(run), before)

func test_manual_sweep_fuse_chain_keeps_single_source_cost_and_normal_scores() -> void:
	var run: RunController = _run()
	run.start_turn()
	run.state.line_clear.upgrades[MANUAL.skill_id] = 1
	var source: PieceState = run.abilities.add_line_piece(1, Vector2i.ZERO, 0)
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(0, 2), 1)
	run.abilities.assign_fuse(fuse.piece_id)
	run.abilities.upgrade_reward()
	run.state.rules.place_piece(Vector2i(1, 2), 2)
	var result: CommandResult = run.execute_command(_command(run, source))
	assert_true(result.accepted)
	assert_eq(result.turn.matches.size(), 2)
	assert_eq(result.turn.matches[0].score_entry.final_score, 6)
	assert_eq(result.turn.matches[1].score_entry.final_score, 5)
	assert_eq(result.turn.matches[1].generation, 2)
	assert_eq(run.state.activations, 1)
	assert_eq(run.state.ledger.total, 11)

func test_command_codec_record_file_replay_and_analysis_cover_manual_action() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", true)
	var source: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(Vector2i.ZERO))
	var command: ActivateLineCommand = _command(run, source)
	assert_eq(CommandCodec.encode(CommandCodec.decode(CommandCodec.encode(command))), CommandCodec.encode(command))
	assert_true(run.execute_command(command).accepted)
	_finish_action(run)
	run.recorder.finish(run, "abandoned", "manual_line_fixture")
	assert_eq(run.recorder.error, "")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))
	var analysis: RunAnalysis = RunAnalysis.new()
	analysis.add(run.recorder.records)
	assert_eq(analysis.turns.size(), 1)
	assert_eq(analysis.turns[0].command_type, "activate_line")

func test_bots_enumerate_manual_actions_without_touching_game_random() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line")
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var bot: RandomLegalBot = RandomLegalBot.new(4)
	var commands: Array[ActivateLineCommand] = bot.legal_line_activations(run)
	assert_eq(commands.size(), 2)
	for command: ActivateLineCommand in commands: assert_eq(command.source, "bot")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
