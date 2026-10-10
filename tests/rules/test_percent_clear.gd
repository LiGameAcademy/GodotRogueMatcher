extends GutTest

const SKILL: SkillDefinition = preload("res://gameplay/progression/content/instant_percent_clear.tres")

func _run(count: int = 8) -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = [1, 1]
	config.pressure_intervals = [4, 4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 37, config)
	for index: int in range(count):
		run.state.rules.place_piece(Vector2i(index % 9, index / 9), index % 5)
	run.state.rewards.consumed_count = 2
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func _offer(run: RunController) -> SkillOffer:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 3
	offer.choices = [SKILL]
	offer.targets[SKILL.skill_id] = SKILL.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	run.state.rewards.active_offer = offer
	return offer

func test_floor_zero_and_invalid_ratio() -> void:
	for count: int in range(13):
		var run: RunController = _run(count)
		var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
		assert_eq(SKILL.choice_effect.rejection(context).is_empty(), count >= 4)
		var before: int = run.state.rewards.target_random.state
		var target: SkillTarget = SKILL.choice_effect.freeze(context, run.state.rewards.target_random)
		assert_eq(target.piece_ids.size(), count / 4)
		if count < 4: assert_eq(run.state.rewards.target_random.state, before)
	var config: PercentClearEffect = SKILL.choice_effect.duplicate() as PercentClearEffect
	for ratio: float in [0.0, -0.1, 1.1, NAN]:
		config.ratio = ratio
		assert_false(config.rejection(SkillRules.effect_context(_run().state)).is_empty())
	assert_eq((SKILL.choice_effect as PercentClearEffect).ratio, 0.25)

func test_freeze_is_unique_reproducible_and_preserves_board_random() -> void:
	for seed_value: int in range(64):
		var run: RunController = _run(40)
		run.state.rewards.target_random.seed = seed_value
		var random: int = run.state.random.state
		var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
		var target: SkillTarget = SKILL.choice_effect.freeze(context, run.state.rewards.target_random)
		assert_eq(target.piece_ids.size(), 10)
		var ids: Array[int] = []
		for id: int in target.piece_ids:
			assert_false(ids.has(id))
			ids.append(id)
		var other: RandomNumberGenerator = RandomNumberGenerator.new()
		other.seed = seed_value
		assert_eq(SKILL.choice_effect.freeze(context, other).piece_ids, target.piece_ids)
		assert_eq(run.state.random.state, random)

func test_plain_clear_preserves_partner_score_turn_and_refill() -> void:
	var run: RunController = _run(8)
	var core: PieceState = run.abilities.add_core(Vector2i(8, 8))
	var offer: SkillOffer = _offer(run)
	assert_false((offer.targets[SKILL.skill_id] as SkillTarget).piece_ids.has(core.piece_id))
	var refill: int = run.state.next_refill_count()
	var turn: int = run.state.turn_count
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, SKILL.skill_id)
	assert_true(result.success, result.error)
	assert_eq(result.removed.size(), 2)
	assert_not_null(run.state.rules.state.get_piece(core.piece_id))
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.turn_count, turn)
	assert_eq(run.state.next_refill_count(), refill)
	assert_eq(run.state.pending_rewards, 0)
	assert_false(SkillRules.apply(run, offer.offer_id, SKILL.skill_id).success)

func test_stale_and_duplicate_targets_do_not_consume_reward() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run)
	var target: SkillTarget = offer.targets[SKILL.skill_id]
	target.piece_ids[1] = target.piece_ids[0]
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, SKILL.skill_id).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	run = _run()
	offer = _offer(run)
	target = offer.targets[SKILL.skill_id]
	run.state.rules.remove_piece(target.piece_ids[0])
	before = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, SKILL.skill_id).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_fuse_can_be_selected_and_descendants_use_normal_score() -> void:
	var run: RunController = _run(4)
	var fuse: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(Vector2i(1, 0)))
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.explosion.reward_level = 1
	var offer: SkillOffer = _offer(run)
	# 固定一个合法冻结目标，验证执行链；随机无放回另有测试。
	(offer.targets[SKILL.skill_id] as SkillTarget).piece_ids = [fuse.piece_id]
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, SKILL.skill_id)
	assert_true(result.success, result.error)
	assert_gt(result.matches.size(), 0)
	assert_gt(run.state.ledger.total, 0)
	assert_eq(run.state.stage.missing_score(), 0)
	assert_eq(run.state.stage.used_actions, 0, "选卡得分推进目标，但不替代新有效行动")
	for entry: ScoreEntry in run.state.ledger.get_entries():
		assert_eq(entry.reason, &"explosion")
		assert_eq(entry.base_score, 0)

func test_candidate_and_preview_use_frozen_count() -> void:
	var run: RunController = _run(7)
	var offer: SkillOffer = _offer(run)
	assert_string_contains(SkillChoiceText.compact_preview(SKILL, offer.targets[SKILL.skill_id]), "1枚")
	assert_same(SkillOfferGenerator.new().generate(run), offer)
	var small: RunController = _run(3)
	assert_false(SkillRules.rejection(small.state, SKILL, small.abilities.config, 100.0).is_empty())
	assert_eq(RescueOfferRules.factor(run.state, SKILL, 100.0), 2.2)

func test_actual_percent_choice_replays_every_checkpoint() -> void:
	var chosen: bool = false
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
		for step: int in range(100):
			if run.state.is_game_over or not run.state.rule_error.is_empty(): break
			if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
				run.advance()
				continue
			if run.state.phase not in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
				run.advance()
				continue
			var command: RunCommand = bot.choose(run)
			if command == null: break
			var result: CommandResult = run.execute_command(command)
			assert_true(result.accepted, result.reason)
			if command is ChooseSkillCommand and (command as ChooseSkillCommand).skill_id == SKILL.skill_id:
				chosen = true
				break
		if not chosen: continue
		run.recorder.finish(run, "abandoned", "test_complete")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay(run.recorder.records), replay.error)
		assert_eq(replay.checked_records, run.recorder.records.size())
		break
	assert_true(chosen, "通过正常候选抽选实际取得比例卡，不注入候选或结算结果")
