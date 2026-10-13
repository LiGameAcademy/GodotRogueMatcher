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

func test_catalog_clear_dye_does_not_end_a_valid_two_color_run() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i(0, 0), 0)
	run.state.rules.place_piece(Vector2i(1, 0), 1)
	var skill: SkillDefinition = preload("res://gameplay/progression/content/composite_clear_dye.tres")
	assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "")
	var offer: SkillOffer = _offer(run, skill)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id, 0)
	print("REVIEW two-color: success=", result.success, " error=", result.error,
		" phase=", RunState.Phase.keys()[run.state.phase], " pieces=", run.state.rules.state.get_piece_count(),
		" rewards=", run.state.pending_rewards)
	assert_true(result.success, "当前正常候选应可安全取得或在提交前拒绝")
	assert_eq(run.state.rule_error, "")



func test_standalone_dye_still_rejects_missing_targets() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i.ZERO, 0)
	var effect: DyeMaterialEffect = DyeMaterialEffect.new()
	var context: ChoiceEffectContext = SkillRules.effect_context(run.state)
	assert_false(effect.rejection(context).is_empty())
	assert_false(effect.build(context, effect.freeze(context, run.state.rewards.target_random)).error.is_empty())

func test_configured_empty_dye_does_not_hide_invalid_live_targets() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i.ZERO, 0)
	run.state.rules.place_piece(Vector2i.ONE, 1)
	var effect: DyeMaterialEffect = DyeMaterialEffect.new()
	effect.allow_empty_targets = true
	assert_false(effect.build(SkillRules.effect_context(run.state), SkillTarget.new()).error.is_empty())

func test_configured_empty_board_dye_is_legal() -> void:
	var run: RunController = _run()
	var effect: DyeMaterialEffect = DyeMaterialEffect.new()
	effect.allow_empty_targets = true
	assert_eq(effect.build(SkillRules.effect_context(run.state), SkillTarget.new()).error, "")
