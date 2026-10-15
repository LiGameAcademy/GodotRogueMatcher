extends GutTest

## Every shipped card is exercised through the same command/freeze/runner/record path as gameplay.
func _run(skill: SkillDefinition) -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = [10000]
	config.pressure_intervals = [4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 83, config)
	run.state.explosion.core_pool_unlocked = skill.skill_id != &"core_drop"
	run.state.explosion.fuse_unlocked = true
	run.state.line_clear.row_unlocked = skill.skill_id != &"line_row_drop"
	run.state.line_clear.column_unlocked = skill.skill_id != &"line_column_drop"
	run.state.explosion.unlocked = true
	for prerequisite: StringName in [&"core_manual_detonation", &"fuse_relay", &"match_dye_echo"]:
		run.state.rewards.acquired[prerequisite] = 1
	run.state.rewards.consumed_count = 5
	for color: int in range(5):
		run.state.rules.place_piece(Vector2i(color, 1), color)
	run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i(0, 1)))
	return run

func _choose(run: RunController, skill: SkillDefinition) -> ChooseSkillCommand:
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
	command.selected_color = 1 if skill.requires_color_choice(SkillRules.level(run.state, skill)) else -1
	return command

func test_every_catalog_card_uses_command_pipeline_and_records_all_score_events() -> void:
	var seen: Array[StringName] = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		assert_false(seen.has(skill.skill_id))
		seen.append(skill.skill_id)
		var run: RunController = _run(skill)
		assert_eq(skill.validation_error(), "", String(skill.skill_id))
		assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "", String(skill.skill_id))
		var config_before: String = RunSnapshot.digest(RunSnapshot.config(run))
		var command: ChooseSkillCommand = _choose(run, skill)
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "test", false)
		var result: CommandResult = run.execute_command(command)
		assert_true(result.accepted, "%s: %s" % [skill.skill_id, result.reason])
		if not result.accepted: continue
		if skill.acquisition_effect() is UnlockLineSupplyEffect:
			assert_eq(result.skill.created.size(), 1, "%s must place its first sweeper" % skill.skill_id)
			var axis: int = (skill.acquisition_effect() as UnlockLineSupplyEffect).axis
			assert_true(run.state.line_clear.unlocked(axis), String(skill.skill_id))
		assert_eq(run.state.rule_error, "", String(skill.skill_id))
		assert_eq(run.state.pending_rewards, 0)
		assert_eq(run.state.rewards.acquired.get(skill.skill_id, 0), 1 if skill.skill_id not in [&"core_manual_detonation", &"fuse_relay", &"match_dye_echo"] else 2)
		assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config_before)
		var recorded_score: int = 0
		var found_result: bool = false
		for record: Dictionary in run.recorder.records:
			if record.kind == "RuleResult":
				found_result = true
				for event: Dictionary in record.events: recorded_score += int(event.score.final_score)
		assert_true(found_result, String(skill.skill_id))
		assert_eq(recorded_score, run.state.ledger.total, String(skill.skill_id))
		var after: String = RunSnapshot.digest(RunSnapshot.capture(run))
		var records_before: int = run.recorder.records.size()
		assert_same(run.execute_command(command), result)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), after)
		assert_eq(run.recorder.records.size(), records_before)
	assert_eq(seen.size(), 49)

func test_all_declared_level_upgrades_use_frozen_targets_and_preserve_instance() -> void:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.levels.size() < 2: continue
		var run: RunController = _run(skill)
		var previous: SkillInstance = null
		for expected: int in range(1, skill.maximum_level + 1):
			var result: CommandResult = run.execute_command(_choose(run, skill))
			assert_true(result.accepted, "%s level %d: %s" % [skill.skill_id, expected, result.reason])
			if not result.accepted: break
			var instance: SkillInstance = run.state.skill_instances[skill.skill_id]
			assert_eq(instance.level, expected)
			assert_eq(instance.abilities[0].trigger_count, expected)
			if previous != null: assert_same(instance, previous)
			previous = instance
		assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "已满级", String(skill.skill_id))
