extends GutTest

const CORE: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
const SUPPLY: SkillDefinition = preload("res://gameplay/progression/content/core_supply_up.tres")

func _run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)

func _offer(run: RunController, skill: SkillDefinition) -> SkillOffer:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	var current: int = SkillRules.level(run.state, skill)
	var effect: SkillEffect = skill.acquisition_effect(current)
	var target: SkillTarget = (effect as ChoiceEffect).freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	target.level_before = current
	target.level_after = current + 1
	offer.targets[skill.skill_id] = target
	run.state.rewards.active_offer = offer
	return offer

func _apply(run: RunController, skill: SkillDefinition) -> SkillApplyResult:
	var offer: SkillOffer = _offer(run, skill)
	return SkillRules.apply(run, offer.offer_id, skill.skill_id)

func test_shared_definitions_and_independent_instances_with_no_template_writes() -> void:
	var first: RunController = _run()
	var second: RunController = _run()
	var before: String = RunSnapshot.digest(RunSnapshot.config(first))
	assert_eq(CORE.validation_error(), "")
	assert_eq(SUPPLY.validation_error(), "")
	assert_true(_apply(first, CORE).success)
	assert_true(_apply(second, CORE).success)
	assert_true(_apply(first, SUPPLY).success)
	assert_true(_apply(second, SUPPLY).success)
	var a: SkillInstance = first.state.skill_instances[SUPPLY.skill_id]
	var b: SkillInstance = second.state.skill_instances[SUPPLY.skill_id]
	assert_same(a.definition, b.definition)
	assert_not_same(a, b)
	assert_not_same(a.abilities[0], b.abilities[0])
	assert_true(_apply(first, SUPPLY).success)
	assert_eq(a.level, 2)
	assert_eq(b.level, 1)
	assert_eq(b.abilities[0].trigger_count, 1)
	assert_eq(second.state.explosion.level(&"core_supply_up"), 1)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(first)), before)

func test_upgrade_retains_ability_identity_count_and_authoritative_level() -> void:
	var run: RunController = _run()
	assert_true(_apply(run, CORE).success)
	assert_true(_apply(run, SUPPLY).success)
	var instance: SkillInstance = run.state.skill_instances[SUPPLY.skill_id]
	var ability: AbilityInstance = instance.abilities[0]
	var instance_id: int = instance.instance_id
	var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	assert_true(_apply(run, SUPPLY).success)
	assert_same(instance.abilities[0], ability)
	assert_eq(instance.instance_id, instance_id)
	assert_eq(ability.skill_instance_id, instance_id)
	assert_eq(ability.trigger_count, 2)
	assert_eq(ability.definition.event_type, &"skill_upgraded")
	assert_eq(SkillRules.level(run.state, SUPPLY), 2)
	assert_eq(run.state.explosion.level(&"core_supply_up"), 2)
	assert_false(SkillRules.rejection(run.state, SUPPLY, run.abilities.config).is_empty())
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)
	# 取得次数是历史，不再作为迁移技能的等级或构筑显示来源。
	run.state.rewards.acquired.clear()
	assert_eq(SkillRules.level(run.state, SUPPLY), 2)
	assert_has(HudDetails.active_skills(run.state), SUPPLY)

func test_failed_core_target_does_not_consume_or_install_any_state() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run, CORE)
	var target: SkillTarget = offer.targets[CORE.skill_id]
	run.state.rules.place_piece(target.coordinate, 0)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, CORE.skill_id).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_true(run.state.skill_instances.is_empty())
	assert_false(run.state.explosion.core_pool_unlocked)
	assert_eq(run.state.pending_rewards, 1)

func test_failed_upgrade_does_not_reset_count_or_consume_reward() -> void:
	var run: RunController = _run()
	assert_true(_apply(run, CORE).success)
	assert_true(_apply(run, SUPPLY).success)
	var instance: SkillInstance = run.state.skill_instances[SUPPLY.skill_id]
	var offer: SkillOffer = _offer(run, SUPPLY)
	offer.targets[SUPPLY.skill_id].value_before = 0
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, SUPPLY.skill_id).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(instance.level, 1)
	assert_eq(instance.abilities[0].trigger_count, 1)

func test_core_leaving_keeps_unlock_and_skills_and_reset_discards_instances() -> void:
	var run: RunController = _run()
	var acquired: SkillApplyResult = _apply(run, CORE)
	assert_true(acquired.success)
	assert_true(_apply(run, SUPPLY).success)
	run.abilities.resolve_removal(acquired.created, &"skill_clear")
	assert_true(run.state.explosion.core_pool_unlocked)
	assert_eq(SkillRules.level(run.state, CORE), 1)
	assert_eq(SkillRules.level(run.state, SUPPLY), 1)
	assert_true(run.state.explosion.instances.is_empty())
	assert_true(_apply(run, SUPPLY).success)
	var old: SkillInstance = run.state.skill_instances[SUPPLY.skill_id]
	run.state.reset_counters()
	assert_true(run.state.skill_instances.is_empty())
	assert_false(run.state.explosion.core_pool_unlocked)
	assert_eq(run.state.explosion.level(&"core_supply_up"), 0)
	assert_eq(old.level, 2)

func test_invalid_levels_and_wrong_effect_types_are_rejected_before_changes() -> void:
	var run: RunController = _run()
	var broken: SkillDefinition = SUPPLY.duplicate(true) as SkillDefinition
	broken.levels[1].level = 3
	assert_false(broken.validation_error().is_empty())
	broken = SUPPLY.duplicate(true) as SkillDefinition
	broken.levels[1].abilities[0].ability_id = &"different"
	assert_false(broken.validation_error().is_empty())
	broken = SUPPLY.duplicate(true) as SkillDefinition
	broken.levels[0].abilities[0].effect = ExplodeEffect.new()
	assert_false(broken.validation_error().is_empty())
	broken = CORE.duplicate(true) as SkillDefinition
	broken.levels.clear()
	assert_false(SkillRules.rejection(run.state, broken, run.abilities.config).is_empty())
	assert_true(run.state.skill_instances.is_empty())

func test_snapshot_includes_runtime_counts_and_nested_level_config() -> void:
	var run: RunController = _run()
	assert_true(_apply(run, CORE).success)
	assert_true(_apply(run, SUPPLY).success)
	assert_true(_apply(run, SUPPLY).success)
	var snapshot: Dictionary = RunSnapshot.capture(run)
	assert_eq(snapshot.skills.size(), 2)
	assert_eq(snapshot.skills[1].level, "2")
	assert_eq(snapshot.skills[1].abilities[0].trigger_count, "2")
	var config: Dictionary = RunSnapshot.resource_fields(SUPPLY)
	assert_eq(config.levels[1].parameters.abilities[0].parameters.event_type, "skill_upgraded")
	assert_eq(config.levels[1].parameters.abilities[0].parameters.effect.parameters.upgrade, "core_supply_up")

func test_desynchronized_modifier_refuses_upgrade_without_consumption() -> void:
	var run: RunController = _run()
	assert_true(_apply(run, CORE).success)
	assert_true(_apply(run, SUPPLY).success)
	var offer: SkillOffer = _offer(run, SUPPLY)
	run.state.explosion.upgrades[&"core_supply_up"] = 0
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, SUPPLY.skill_id).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_actual_commands_replay_acquisition_and_upgrade_instances() -> void:
	# 较多小目标仅为触发取得/升级的测试配置，不进入运行目标资源。
	var seen: bool = false
	for seed_value: int in range(4):
		var config: StageConfig = StageConfig.new()
		for stage: int in range(20):
			config.targets.append(1)
			config.pressure_intervals.append(4)
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, config)
		run.initialize()
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "test", false)
		var bot: GreedyBot = GreedyBot.new(seed_value)
		for step: int in range(600):
			if run.state.is_game_over or not run.state.rule_error.is_empty(): break
			if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
				run.advance()
			elif run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
				var command: RunCommand = bot.choose(run)
				var offer: SkillOffer = run.state.rewards.active_offer
				if offer != null:
					for id: StringName in [&"core_drop", &"core_supply_up"]:
						if offer.targets.has(id):
							command = bot.skill_command(run, id)
							break
				if command == null: break
				assert_true(run.execute_command(command).accepted)
			else: run.advance()
			if SkillRules.level(run.state, SUPPLY) == 2:
				seen = true
				break
		if not seen: continue
		run.recorder.finish(run, "abandoned", "test_complete")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay(run.recorder.records), replay.error)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))
		assert_eq(replay.run.state.skill_instances[SUPPLY.skill_id].abilities[0].trigger_count, 2)
		break
	assert_true(seen, "真实命令取得核心与两级补给后精确回放，无注入候选或结果")
