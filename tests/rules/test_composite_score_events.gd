extends GutTest

func _run(run_seed: int = 7) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), run_seed)

func _offer(run: RunController, skill: SkillDefinition) -> SkillOffer:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	return offer

func test_catalog_clear_dye_keeps_first_leaf_score_events() -> void:
	var run: RunController = _run()
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(0, 0), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.explosion.upgrades[&"marked_reward"] = 1
	run.state.rules.place_piece(Vector2i(7, 7), 1)
	run.state.rules.place_piece(Vector2i(8, 8), 2)
	var skill: SkillDefinition = preload("res://gameplay/progression/content/composite_clear_dye.tres")
	var offer: SkillOffer = _offer(run, skill)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id, 0)
	assert_true(result.success, result.error)
	var ledger_reward: bool = false
	var returned_reward: bool = false
	for entry: ScoreEntry in run.state.ledger.get_entries():
		if entry.reason == &"marked_reward": ledger_reward = true
	for value: MatchResult in result.matches:
		if value.score_entry.reason == &"marked_reward": returned_reward = true
	print("REVIEW marked reward: ledger=", ledger_reward, " returned=", returned_reward,
		" total=", run.state.ledger.total)
	assert_true(ledger_reward)
	assert_true(returned_reward, "第一叶子得分必须保留在返回给表现/采集的结果中")
	assert_eq(result.matches[0].score_entry.reason, &"marked_reward")
	var events: Array[Dictionary] = RunRecorder.matches(result.matches)
	var recorded_total: int = 0
	var recorded_reward: bool = false
	for event: Dictionary in events:
		recorded_total += int(event.score.final_score)
		if String(event.score.reason) == "marked_reward": recorded_reward = true
	assert_true(recorded_reward, "采集序列化保留前序奖励事件")
	assert_eq(recorded_total, run.state.ledger.total)



func test_core_creation_keeps_prior_leaf_results() -> void:
	var run: RunController = _run()
	var result: SkillApplyResult = SkillApplyResult.new()
	var previous: MatchResult = MatchResult.new()
	result.matches.append(previous)
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.UNLOCK_CORE
	request.coordinate = Vector2i.ZERO
	request.color = 2
	assert_eq(AbilityEffectRunner.apply_choice_request(run, request, result), "")
	assert_eq(result.created.size(), 1)
	assert_eq(result.matches.size(), 1)
	assert_same(result.matches[0], previous)
