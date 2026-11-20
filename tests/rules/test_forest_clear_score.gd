extends GutTest

const CARD: SkillDefinition = preload("res://gameplay/progression/content/instant_line_clear.tres")

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.state.rewards.consumed_count = 2
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func _offer(run: RunController, axis: int = 0, line: int = 4) -> SkillOffer:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 3
	offer.choices = [CARD]
	var target: SkillTarget = SkillRules.freeze_target(run.state, CARD, run.state.rewards.target_random)
	target.line_axis = axis
	target.line_index = line
	target.piece_ids.clear()
	for piece: PieceState in run.state.rules.state.get_snapshot():
		if not piece.content_id.is_empty(): continue
		if (piece.coordinate.y if axis == 0 else piece.coordinate.x) == line: target.piece_ids.append(piece.piece_id)
	offer.targets[CARD.skill_id] = target
	run.state.rewards.active_offer = offer
	return offer

func test_row_clear_scores_mixed_colors_and_keeps_specials() -> void:
	var run: RunController = _run()
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 4), x)
	var special: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(6, 4), 2)
	var offer: SkillOffer = _offer(run)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, CARD.skill_id)
	assert_true(result.success, result.error)
	assert_eq(run.state.ledger.total, 50)
	assert_not_null(run.state.rules.state.get_piece(special.piece_id))
	assert_eq(result.removed.size(), 0, "直接消除由带分数的结果统一播放，避免双播")
	assert_eq(result.matches.size(), 1)
	if result.matches.is_empty(): return
	assert_eq(result.matches[0].removed.size(), 5)
	assert_eq(result.matches[0].cause, &"skill_clear")

func test_column_clear_scores_even_below_five_targets() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i(4, 0), 0)
	run.state.rules.place_piece(Vector2i(4, 6), 3)
	var survivor: PieceState = run.state.rules.place_piece(Vector2i(5, 0), 1)
	var offer: SkillOffer = _offer(run, 1)
	assert_true(SkillRules.apply(run, offer.offer_id, CARD.skill_id).success)
	assert_eq(run.state.ledger.total, 14)
	assert_not_null(run.state.rules.state.get_piece(survivor.piece_id))

func test_fuse_chain_scores_separately_and_global_modifiers_apply_to_direct_clear() -> void:
	var run: RunController = _run()
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 4), x)
	var fuse: int = run.state.rules.state.get_piece_id(Vector2i(2, 4))
	run.abilities.assign_fuse(fuse)
	run.abilities.upgrade_reward()
	run.state.explosion.multiplier_level = 1
	run.state.explosion.match_extra_level = 2
	run.state.explosion.upgrades[&"precision_reward"] = 100
	var neighbor: PieceState = run.state.rules.place_piece(Vector2i(2, 5), 1)
	var offer: SkillOffer = _offer(run)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, CARD.skill_id)
	assert_true(result.success, result.error)
	assert_eq(result.matches.size(), 2)
	if result.matches.size() != 2: return
	assert_eq(result.matches[0].score_entry.base_score, 50)
	assert_eq(result.matches[0].score_entry.final_score, 80)
	assert_eq(result.matches[1].cause, &"explosion")
	assert_eq(result.matches[1].score_entry.final_score, 5)
	assert_eq(run.state.ledger.total, 85)
	assert_null(run.state.rules.state.get_piece(neighbor.piece_id))
	assert_eq(run.state.explosion.instances.size(), 0)

func test_rejected_frozen_target_keeps_board_score_and_reward() -> void:
	var run: RunController = _run()
	var piece: PieceState = run.state.rules.place_piece(Vector2i(0, 4), 0)
	var offer: SkillOffer = _offer(run)
	run.state.rules.remove_piece(piece.piece_id)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, CARD.skill_id).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_budget_rejection_keeps_direct_score_uncommitted() -> void:
	var run: RunController = _run()
	var piece: PieceState = run.state.rules.place_piece(Vector2i(0, 4), 0)
	run.abilities.assign_fuse(piece.piece_id)
	var offer: SkillOffer = _offer(run)
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities.config = config
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, CARD.skill_id)
	assert_false(result.success)
	assert_true(result.error.contains("budget"))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_command_duplicate_preserves_score_and_recorded_events() -> void:
	var run: RunController = _run()
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 4), x)
	var offer: SkillOffer = _offer(run)
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "test", false)
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = CARD.skill_id
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted, result.reason)
	var found: bool = false
	for record: Dictionary in run.recorder.records:
		if record.kind != "RuleResult": continue
		assert_eq(record.events.size(), 1)
		assert_eq(record.events[0].score.final_score, "50")
		assert_eq(record.events[0].cause, "skill_clear")
		found = true
	assert_true(found)
	var count: int = run.recorder.records.size()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), result)
	assert_eq(run.recorder.records.size(), count)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(run.state.ledger.total, 50)
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.skill(result.skill, 0.1)
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].matches[0].removed.size(), 5)

func test_scored_skip_invalid_composite_keeps_scoring_policy() -> void:
	var run: RunController = _run()
	var dead: PieceState = run.state.rules.place_piece(Vector2i(0, 4), 0)
	var survivor: PieceState = run.state.rules.place_piece(Vector2i(1, 4), 1)
	var clear: ClearMaterialEffect = ClearMaterialEffect.new()
	clear.target_policy = ChoiceEffect.TargetPolicy.FIXED
	clear.selector = ClearMaterialEffect.Selector.LINE
	clear.score_cleared = true
	var refill: RefillCountEffect = RefillCountEffect.new()
	refill.delta = -1
	refill.batches = 3
	var composite: CompositeEffect = CompositeEffect.new()
	composite.fixed_target_policy = CompositeEffect.FixedTargetPolicy.SKIP_INVALID
	composite.children = [refill, clear]
	var definition: AbilityDefinition = AbilityDefinition.new()
	definition.ability_id = &"scored_composite"
	definition.event_type = &"skill_acquired"
	definition.effect = composite
	var level: SkillLevelDefinition = SkillLevelDefinition.new()
	level.level = 1
	level.abilities = [definition]
	var skill: SkillDefinition = SkillDefinition.new()
	skill.offer_traits = SkillOfferTraits.new()
	skill.offer_traits.roles = [&"generic"]
	skill.skill_id = &"scored_composite"
	skill.maximum_level = 1
	skill.is_persistent = true
	skill.levels = [level]
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 3
	offer.choices = [skill]
	var frozen: CompositeSkillTarget = composite.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) as CompositeSkillTarget
	frozen.leaf_targets[1].line_axis = 0
	frozen.leaf_targets[1].line_index = 4
	frozen.leaf_targets[1].piece_ids = [dead.piece_id, survivor.piece_id]
	offer.targets[skill.skill_id] = frozen
	run.state.rewards.active_offer = offer
	run.state.rules.remove_piece(dead.piece_id)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert_true(result.success, result.error)
	assert_eq(run.state.ledger.total, 6)
	assert_null(run.state.rules.state.get_piece(survivor.piece_id))

func test_other_clear_effects_and_normal_match_threshold_are_unchanged() -> void:
	var clear: ClearMaterialEffect = ClearMaterialEffect.new()
	assert_false(clear.score_cleared)
	var ledger: ScoreLedger = ScoreLedger.new()
	assert_eq(ledger.commit(2).base_score, 0)
	assert_eq(CARD.offer_traits.exception_multiplier, 1.0)

func test_repeated_or_duplicate_removal_targets_never_pay_twice() -> void:
	var run: RunController = _run()
	var first: PieceState = run.state.rules.place_piece(Vector2i(0, 4), 0)
	var second: PieceState = run.state.rules.place_piece(Vector2i(1, 4), 1)
	var result: Array[MatchResult] = run.abilities.resolve_removal([first, first, second], &"skill_clear", false, true)
	assert_eq(result.size(), 1)
	assert_eq(run.state.ledger.total, 14)
	assert_eq(run.abilities.resolve_removal([first, second], &"skill_clear", false, true).size(), 0)
	assert_eq(run.state.ledger.total, 14)
