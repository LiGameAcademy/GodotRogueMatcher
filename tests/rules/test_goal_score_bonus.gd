extends GutTest

const SKILL: SkillDefinition = preload("res://gameplay/progression/content/goal_score_bonus.tres")

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)

func _run(targets: Array[int] = [100, 30, 100]) -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = targets
	for target: int in targets: config.pressure_intervals.append(4)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	run.initialize("fixture_dye")
	return run

func _move(run: RunController, source: Vector2i = Vector2i(4, 6), destination: Vector2i = Vector2i(4, 4)) -> void:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(source)
	command.target = destination
	assert_true(run.execute_command(command).accepted)

func _drain(run: RunController) -> StringName:
	for index: int in range(12):
		var step: RunStepResult = run.advance()
		if step.kind in [&"offer", &"input", &"finished", &"error"]: return step.kind
	fail_test("missing safe boundary")
	return &"error"

func _choose(run: RunController, skill: SkillDefinition) -> void:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillTarget.new() if skill.choice_effect == null else skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = skill.skill_id
	assert_true(run.execute_command(command).accepted)

func test_bonus_is_once_after_action_and_carry_requires_new_action() -> void:
	var run: RunController = _run()
	run.state.goal_bonus_score = 25
	_move(run)
	assert_eq(run.state.ledger.total, 105)
	assert_eq(_drain(run), &"offer")
	var goal: StageResult = run.state.stage.history[0]
	assert_eq(goal.score_total, 105)
	assert_eq(goal.action_score, 105)
	assert_eq(goal.score_after_goal, 130)
	assert_eq(goal.carry_out, 30)
	assert_eq(goal.goal_score_entry.multiplier, 1.0)
	assert_eq(goal.goal_score_entry.root_action_id, 0)
	GoalCompletionRules.resolve(run.state, goal)
	run.advance()
	assert_eq(run.state.ledger.total, 130)
	assert_eq(run.state.pending_rewards, 1)
	_choose(run, preload("res://gameplay/progression/content/match_extra.tres"))
	assert_eq(_drain(run), &"input")
	assert_eq(run.state.stage.used_actions, 0)
	assert_eq(run.state.stage.history.size(), 1)
	assert_eq(run.state.stage.missing_score(), 0)
	_move(run, Vector2i(8, 8), Vector2i(8, 7))
	assert_eq(_drain(run), &"offer")
	assert_eq(run.state.ledger.total, 155)
	assert_eq(run.state.stage.history.size(), 2)

func test_new_choice_does_not_reward_past_goal_and_final_goal_has_no_offer() -> void:
	var run: RunController = _run([100, 1])
	_move(run)
	assert_eq(_drain(run), &"offer")
	# 仅此边界测试放宽刷出阶段；真实候选测试使用原始只读配置。
	var skill: SkillDefinition = SKILL.duplicate() as SkillDefinition
	skill.minimum_reward = 1
	_choose(run, skill)
	assert_eq(run.state.ledger.total, 105)
	assert_eq(SkillRules.level(run.state, SKILL), 1)
	assert_eq(_drain(run), &"input")
	_move(run, Vector2i(8, 8), Vector2i(8, 7))
	assert_eq(_drain(run), &"finished")
	assert_eq(run.state.ledger.total, 130)
	assert_eq(run.state.pending_rewards, 0)
	assert_null(run.prepare_offer())
	assert_eq(run.state.stage.history.back().carry_out, 0)
	assert_eq(run.state.stage.history[0].goal_bonus_score, 0)
	assert_eq(SKILL.minimum_reward, 2)

func test_shortfall_and_full_board_never_trigger_bonus() -> void:
	var run: RunController = _run([106])
	run.state.goal_bonus_score = 25
	_move(run)
	assert_eq(_drain(run), &"input")
	assert_eq(run.state.ledger.total, 105)
	assert_true(run.state.stage.history.is_empty())
	var goal: StageResult = StageResult.new()
	goal.reason = &"board_full"
	GoalCompletionRules.resolve(run.state, goal)
	assert_false(goal.goal_completed)
	assert_eq(run.state.ledger.total, 105)

func test_configuration_eligibility_stale_target_and_reset() -> void:
	var classic: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	assert_false(SKILL.choice_effect.rejection(SkillRules.effect_context(classic.state)).is_empty())
	var run: RunController = _run()
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	var target: SkillTarget = SKILL.choice_effect.freeze(context, run.state.rewards.target_random)
	context.goal_bonus_score = 25
	assert_false(SKILL.choice_effect.build(context, target).error.is_empty())
	var effect: InstallGoalBonusEffect = SKILL.choice_effect.duplicate() as InstallGoalBonusEffect
	effect.bonus_score = 0
	assert_false(effect.rejection(SkillRules.effect_context(run.state)).is_empty())
	assert_eq((SKILL.choice_effect as InstallGoalBonusEffect).bonus_score, 25)
	run.state.goal_bonus_score = 25
	run.state.reset_counters()
	assert_eq(run.state.goal_bonus_score, 0)

func test_telemetry_separates_action_score_and_goal_reward() -> void:
	var run: RunController = _run()
	run.state.goal_bonus_score = 25
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", false)
	_move(run)
	_draining_telemetry(run)

func _draining_telemetry(run: RunController) -> void:
	assert_eq(_drain(run), &"offer")
	var projector: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "goal-test")
	var goals: int = 0
	var bonuses: int = 0
	for row: Dictionary in run.recorder.records: projector.observe_record(row)
	for event: Dictionary in projector.events:
		if event.event_name == "action_resolved":
			assert_eq(event.payload.action_score_delta, "105")
		if event.event_name == "stage_goal_completed":
			goals += 1
			assert_eq(event.payload.result.goal_bonus_score, "25")
			assert_eq(event.payload.P_before, event.payload.P_after)
		if event.event_name == "rule_fact" and event.payload.get("batch_kind") == "goal_completed":
			bonuses += 1
			assert_null(event.root_action_id)
			assert_eq(event.payload.score.final_score, "25")
	assert_eq(goals, 1)
	assert_eq(bonuses, 1)
	assert_eq(projector.error, "")

func test_actual_choice_and_goal_bonus_replay_every_checkpoint() -> void:
	var rewarded: bool = false
	for seed_value: int in range(32):
		var config: StageConfig = StageConfig.new()
		config.targets = [1, 1, 1, 1, 1, 1, 1, 1]
		config.pressure_intervals = [10, 10, 10, 10, 10, 10, 10, 10]
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, config)
		run.initialize("fixture_f6")
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "test", false)
		var bot: GreedyBot = GreedyBot.new(seed_value)
		bot.config = bot.config.duplicate(true) as BotConfig
		bot.config.skill_weights[SKILL.skill_id] = 10000.0
		for index: int in range(100):
			if run.state.is_game_over or not run.state.rule_error.is_empty(): break
			if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
				run.advance()
				continue
			if run.state.phase not in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
				run.advance()
				continue
			var command: RunCommand = bot.choose(run)
			if command == null: break
			assert_true(run.execute_command(command).accepted)
			for goal: StageResult in run.state.stage.history:
				if goal.goal_bonus_score > 0: rewarded = true
			if rewarded: break
		if not rewarded: continue
		run.recorder.finish(run, "abandoned", "test_complete")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay(run.recorder.records), replay.error)
		assert_eq(replay.checked_records, run.recorder.records.size())
		break
	assert_true(rewarded, "正常抽选过关嘉奖，并在后续目标触发奖励与回放")
