extends GutTest

const SCORE: SkillDefinition = preload("res://gameplay/progression/content/line_clear_score.tres")
const MANUAL: SkillDefinition = preload("res://gameplay/progression/content/line_manual_clear.tres")
const ROW: SkillDefinition = preload("res://gameplay/progression/content/line_row_drop.tres")

func _acquire(run: RunController, skill: SkillDefinition) -> void:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = skill.skill_id
	assert_true(run.execute_command(command).accepted)

func _run(seed_value: int, level: int, challenge: bool = false) -> RunController:
	var config: StageConfig = null
	if challenge:
		config = StageConfig.new()
		config.targets = [10000]
		config.pressure_intervals = [4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, config)
	_acquire(run, ROW)
	for index: int in range(level): _acquire(run, SCORE)
	run.state.pending_rewards = 1
	run.enter_rewards()
	run.state.rewards.consumed_count = maxi(2, run.state.rewards.consumed_count)
	return run

func test_score_weight_stays_above_unowned_manual_without_level_or_history_penalties() -> void:
	for level: int in range(3):
		var run: RunController = _run(75, level)
		assert_eq(SkillRules.rejection(run.state, SCORE, run.abilities.config), "")
		assert_eq(SkillRules.rejection(run.state, MANUAL, run.abilities.config), "")
		var before: float = SkillOfferGenerator.weight(run.state, SCORE)
		assert_gt(before, SkillOfferGenerator.weight(run.state, MANUAL))
		run.state.rewards.previous_unselected = [SCORE.skill_id]
		assert_eq(SkillOfferGenerator.weight(run.state, SCORE), before)
func test_fixed_seed_offers_show_score_more_often_for_acquisition_and_upgrades_in_both_modes() -> void:
	# A deterministic sample of candidate generation, not a claim about long-run player statistics.
	for challenge: bool in [false, true]:
		for level: int in range(3):
			var score_count: int = 0
			var manual_count: int = 0
			for seed_value: int in range(256):
				var run: RunController = _run(seed_value, level, challenge)
				var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
				assert_not_null(offer)
				for skill: SkillDefinition in offer.choices:
					if skill.skill_id == SCORE.skill_id: score_count += 1
					if skill.skill_id == MANUAL.skill_id: manual_count += 1
			assert_gt(score_count, manual_count, "challenge=%s level=%d" % [challenge, level])
			print("Sweep availability: challenge=%s level=%d, harvest=%d/256 manual=%d/256" % [challenge, level, score_count, manual_count])

func test_manual_rarity_limit_and_score_effect_are_preserved() -> void:
	assert_eq(SCORE.rarity, SkillDefinition.Rarity.UNCOMMON)
	assert_eq(MANUAL.rarity, SkillDefinition.Rarity.RARE)
	assert_eq(MANUAL.offer_traits.exception_multiplier, 1.0)
	assert_eq(MANUAL.manual_use_limit, 3)
	assert_eq(SCORE.maximum_level, 3)
	assert_eq(LineClearRules.score_per_target(1), 2)
