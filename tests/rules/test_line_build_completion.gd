extends GutTest

const SCORE: SkillDefinition = preload("res://gameplay/progression/content/line_clear_score.tres")
const DYE_IDS: Array[StringName] = [&"match_dye_echo", &"dye_target_up", &"dye_chain_depth", &"dye_mark_reward", &"blast_dye", &"instant_color_dye"]
const STARTERS: Array[StringName] = [&"core_drop", &"line_row_drop", &"line_column_drop"]

func _run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 75)

func _install(run: RunController) -> CommandResult:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [SCORE]
	offer.targets[SCORE.skill_id] = SkillRules.freeze_target(run.state, SCORE)
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = SCORE.skill_id
	return run.execute_command(command)

func test_score_card_requires_supply_preserves_instance_and_caps_at_three() -> void:
	var run: RunController = _run()
	assert_false(SkillRules.rejection(run.state, SCORE, run.abilities.config).is_empty())
	run.state.line_clear.column_unlocked = true
	var fingerprint: String = RunSnapshot.digest(RunSnapshot.config(run))
	var previous: SkillInstance = null
	for level: int in range(1, 4):
		var target: SkillTarget = SkillRules.freeze_target(run.state, SCORE)
		assert_eq(target.value_before, level - 1)
		assert_eq(target.value_after, level)
		assert_eq(SkillChoiceText.compact_preview(SCORE, target), String(TranslationServer.translate("每枚额外得分：+%d → +%d")) % [(level - 1) * 2, level * 2])
		assert_true(_install(run).accepted)
		var current: SkillInstance = run.state.skill_instances[SCORE.skill_id]
		assert_eq(current.level, level)
		assert_eq(current.abilities[0].trigger_count, level)
		if previous != null: assert_same(current, previous)
		previous = current
	assert_eq(SkillRules.rejection(run.state, SCORE, run.abilities.config), "已满级")
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), fingerprint)
	assert_eq(_run().state.line_clear.level(SCORE.skill_id), 0)

func test_empty_short_and_full_sweeps_add_bonus_after_global_multiplier() -> void:
	for axis: int in [0, 1]:
		for level: int in range(4):
			for count: int in [0, 1, 2, 5]:
				var run: RunController = _run()
				run.state.line_clear.upgrades[SCORE.skill_id] = level
				run.state.explosion.multiplier_level = 1
				run.state.explosion.match_extra_level = 1
				var source: PieceState = run.abilities.add_line_piece(axis, Vector2i.ZERO, 0)
				for index: int in range(1, count + 1):
					run.state.rules.place_piece(Vector2i(index, 0) if axis == 0 else Vector2i(0, index), index % 5)
				var result: MatchResult = run.abilities.resolve_removal([source], &"consume")[0]
				var extra: int = 10 + count * 2 * level if count > 0 else 0
				assert_eq(result.score_entry.extra_score, extra)
				assert_eq(result.score_entry.final_score, floori(count * (count + 5) * 1.2 + extra))
				assert_eq(result.score_entry.target_ids.size(), count)

func test_cross_chain_counts_live_targets_once_and_does_not_bonus_blasts() -> void:
	var baseline: RunController = _run()
	baseline.initialize("fixture_line_cross")
	var upgraded: RunController = _run()
	upgraded.initialize("fixture_line_cross")
	upgraded.state.line_clear.upgrades[SCORE.skill_id] = 3
	var source_id: int = baseline.state.rules.state.get_piece_id(Vector2i(2, 4))
	var plain: Array[MatchResult] = baseline.abilities.resolve_removal([baseline.state.rules.state.get_piece(source_id)], &"consume")
	var bonus: Array[MatchResult] = upgraded.abilities.resolve_removal([upgraded.state.rules.state.get_piece(source_id)], &"consume")
	assert_eq(plain.size(), bonus.size())
	for index: int in range(bonus.size()):
		var expected: int = bonus[index].removed.size() * 6 if bonus[index].cause == &"line_clear" else 0
		assert_eq(bonus[index].score_entry.final_score - plain[index].score_entry.final_score, expected)
		assert_eq(bonus[index].score_entry.target_ids, plain[index].score_entry.target_ids)

func test_normal_match_and_instant_clear_do_not_gain_sweep_bonus() -> void:
	var run: RunController = _run()
	run.state.line_clear.upgrades[SCORE.skill_id] = 3
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 0), 0)
	var result: MatchResult = run.abilities.resolve(run.state.rules.find_matches())[0]
	assert_eq(result.score_entry.extra_score, 0)
	var target: PieceState = run.state.rules.place_piece(Vector2i.ZERO, 1)
	result = run.abilities.resolve_removal([target], &"skill_clear", false, true)[0]
	assert_eq(result.score_entry.extra_score, 0)
	assert_eq(result.score_entry.final_score, 6)

func test_first_slot_contains_all_legal_cards_without_supply_subpool() -> void:
	for challenge: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 75, StageConfig.new() if challenge else null)
		run.state.pending_rewards = 1
		var random: int = run.state.random.state
		var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
		assert_not_null(offer)
		assert_true(offer.slot_log[0].weights.has(&"score_multiplier"))
		for id: StringName in STARTERS: assert_true(offer.slot_log[0].weights.has(id))
		assert_same(SkillOfferGenerator.new().generate(run), offer)
		assert_eq(run.state.random.state, random)

func test_six_dye_cards_have_explicit_mechanism_and_neutral_q_with_hard_prerequisites() -> void:
	var run: RunController = _run()
	var count: int = 0
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if not DYE_IDS.has(skill.skill_id): continue
		count += 1
		assert_eq(skill.offer_traits.exception_multiplier, 1.0)
		assert_true(skill.offer_traits.affinity.has(&"dye"))
		assert_false(skill.offer_traits.affinity.has(&"match"))
		var reason: String = SkillRules.rejection(run.state, skill, run.abilities.config)
		if not reason.is_empty(): assert_eq(SkillOfferGenerator.weight(run.state, skill), 0.0)
	assert_eq(count, 6)
func test_scored_fixture_records_and_replays_real_file() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line_score")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", true)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i.ZERO)
	assert_true(run.execute_command(command).accepted)
	for step: int in range(4):
		if run.state.phase == RunState.Phase.INPUT: break
		run.advance()
	assert_eq(run.state.ledger.total, 18)
	run.recorder.finish(run, "abandoned", "line_score_fixture")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))
