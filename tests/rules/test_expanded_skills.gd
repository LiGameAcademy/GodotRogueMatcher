extends GutTest

const NEW_IDS: Array[StringName] = [&"refill_less", &"refill_more", &"color_weight_up", &"color_weight_down", &"instant_color_clear", &"instant_line_clear"]

func _run(seed_value: int = 7) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.state.rewards.consumed_count = 2
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func _skill(id: StringName) -> SkillDefinition:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id == id: return skill
	return null

func _offer(run: RunController, id: StringName) -> SkillOffer:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	var skill: SkillDefinition = _skill(id)
	offer.choices = [skill]
	offer.targets[id] = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	run.state.rewards.active_offer = offer
	run.enter_rewards()
	return offer

func _apply(run: RunController, id: StringName) -> SkillApplyResult:
	run.state.pending_rewards = 1
	var offer: SkillOffer = _offer(run, id)
	return SkillRules.apply(run, offer.offer_id, id)

func test_32_resources_and_support_skills_can_be_drawn_at_third_reward() -> void:
	assert_eq(SkillOfferGenerator.CATALOG.size(), 32)
	var seen: Array[StringName] = []
	for seed_value: int in range(150):
		var run: RunController = _run(seed_value)
		for x: int in range(5): run.state.rules.place_piece(Vector2i(x, x), x)
		var random_before: int = run.state.random.state
		var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
		assert_not_null(offer)
		var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
		assert_same(SkillOfferGenerator.new().generate(run), offer)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
		assert_eq(run.state.random.state, random_before)
		for skill: SkillDefinition in offer.choices:
			if NEW_IDS.has(skill.skill_id) and not seen.has(skill.skill_id): seen.append(skill.skill_id)
	for id: StringName in NEW_IDS: assert_has(seen, id)

func test_refill_modifier_survives_match_skip_and_lasts_three_actual_batches() -> void:
	var run: RunController = _run()
	run.state.rules.place_piece(Vector2i.ZERO, 0)
	assert_true(_apply(run, &"refill_less").success)
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 2)
	run.continuation = &"after_end"
	run.set("_direct_match", true)
	assert_eq(run.advance().spawns.size(), 0)
	assert_eq(run.state.spawning.refill_batches[-1], 3)
	run.continuation = &"after_end"
	run.set("_direct_match", false)
	assert_eq(run.advance().spawns.size(), 2)
	assert_eq(run.state.spawning.refill_batches[-1], 2)
	for remaining: int in [1, 0]:
		run.continuation = &"after_end"
		assert_eq(run.advance().spawns.size(), 2)
		assert_eq(run.state.spawning.refill_batches[-1], remaining)
	run.continuation = &"after_end"
	assert_eq(run.advance().spawns.size(), 3)
	assert_false(HudDetails.skills(run.state).contains("留白一手"))
	assert_string_contains(HudDetails.history(run.state), "留白一手")

func test_refill_repeat_extends_duration_without_stacking_and_opposites_offset() -> void:
	var run: RunController = _run()
	assert_true(_apply(run, &"refill_less").success)
	assert_true(_apply(run, &"refill_less").success)
	assert_eq(run.state.spawning.refill_batches[-1], 6)
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 2)
	assert_true(_apply(run, &"refill_more").success)
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 3)
	for batch: int in range(3):
		assert_eq(run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG), 3)
	assert_eq(run.state.spawning.refill_batches, {-1: 3, 1: 0})
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 2)
	for batch: int in range(3):
		assert_eq(run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG), 2)
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 3)
	assert_eq(run.state.spawning.refill_batches, {-1: 0, 1: 0})

func test_color_weight_changes_only_selected_color_and_isolates_runs_and_resources() -> void:
	var run: RunController = _run()
	var second: RunController = _run()
	var offer: SkillOffer = _offer(run, &"color_weight_up")
	var target: SkillTarget = offer.targets[&"color_weight_up"]
	var random_before: int = run.state.random.state
	assert_true(SkillRules.apply(run, offer.offer_id, &"color_weight_up").success)
	for color: int in range(5): assert_eq(run.state.spawning.color_weights[color], 6 if color == target.color else 4)
	assert_eq(second.state.spawning.color_weights, [4, 4, 4, 4, 4])
	assert_eq(RunController.SPAWN_CONFIG.color_weights, [4, 4, 4, 4, 4])
	assert_eq(run.state.random.state, random_before)
	run.state.reset_counters()
	assert_eq(run.state.spawning.color_weights, [4, 4, 4, 4, 4])
	assert_eq(run.state.spawning.refill_batches[-1], 0)

func test_weighted_colors_are_deterministic_and_follow_modified_distribution() -> void:
	var state: SpawnState = SpawnState.new(RunController.SPAWN_CONFIG)
	state.color_weights = [20, 2, 2, 2, 2]
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	var second: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = 12
	second.seed = 12
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for index: int in range(2000):
		var color: int = state.draw_color(first)
		assert_eq(color, state.draw_color(second))
		counts[color] += 1
	assert_gt(counts[0], 1300)
	assert_lt(counts[0], 1550)
	for color: int in range(1, 5): assert_gt(counts[color], 90)

func test_color_lowering_stays_positive_and_excludes_capped_targets() -> void:
	var run: RunController = _run()
	for index: int in range(3): assert_true(_apply(run, &"color_weight_down").success)
	assert_eq(run.state.spawning.color_weights.count(2), 3)
	assert_eq(run.state.spawning.color_weights.count(4), 2)
	assert_string_contains(SkillRules.rejection(run.state, _skill(&"color_weight_down"), run.abilities.config), "满级")
	run.state.spawning.color_weights = [2, 2, 2, 2, 2]
	assert_string_contains(_skill(&"color_weight_down").choice_effect.rejection(SkillRules.effect_context(run.state)), "没有")
	run.state.spawning.color_weights = [20, 20, 20, 20, 18]
	run.state.pending_rewards = 1
	var offer: SkillOffer = _offer(run, &"color_weight_up")
	assert_eq((offer.targets[&"color_weight_up"] as SkillTarget).color, 4)
	assert_true(SkillRules.apply(run, offer.offer_id, &"color_weight_up").success)
	assert_string_contains(SkillRules.rejection(run.state, _skill(&"color_weight_up"), run.abilities.config), "没有")

func test_color_clear_triggers_fuse_chain_scores_only_explosions_and_preserves_unhit_partner() -> void:
	var run: RunController = _run()
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(2, 2), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	var next_fuse: PieceState = run.state.rules.place_piece(Vector2i(3, 2), 1)
	run.abilities.assign_fuse(next_fuse.piece_id)
	run.state.rules.place_piece(Vector2i(4, 2), 2)
	var core: PieceState = run.abilities.add_core(Vector2i(8, 8))
	assert_string_contains(PieceTooltip.describe(fuse, run.state.explosion, run.abilities.config), "颜色／行列清理")
	assert_false(PieceTooltip.describe(core, run.state.explosion, run.abilities.config).contains("颜色／行列清理"))
	run.state.explosion.reward_level = 1
	var offer: SkillOffer = _offer(run, &"instant_color_clear")
	var target: SkillTarget = offer.targets[&"instant_color_clear"]
	target.color = 0
	target.piece_ids = [fuse.piece_id]
	var instance: AbilityInstance = run.state.explosion.instances[fuse.piece_id]
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, &"instant_color_clear", 0)
	assert_true(result.success)
	assert_eq(result.removed.size(), 1)
	assert_eq(result.matches.size(), 2)
	assert_eq(result.matches[0].generation, 1)
	assert_eq(result.matches[1].generation, 2)
	assert_eq(run.state.ledger.total, 10)
	assert_eq(instance.trigger_count, 1)
	assert_eq(run.state.explosion.instances.size(), 1)
	assert_eq(run.state.rules.state.get_piece(core.piece_id).coordinate, core.coordinate)
	for entry: ScoreEntry in run.state.ledger.get_entries():
		assert_eq(entry.reason, &"explosion")
		assert_eq(entry.base_score, 0)
		assert_eq(entry.root_action_id, run.state.action_id)

func test_line_clear_freezes_both_axes_removes_all_ordinary_targets_without_direct_score() -> void:
	var run: RunController = _run()
	var core: PieceState = run.abilities.add_core(Vector2i(8, 0))
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 0), x)
	var skill: SkillDefinition = _skill(&"instant_line_clear")
	var axes: Array[int] = []
	for index: int in range(30):
		var target: SkillTarget = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
		if not axes.has(target.line_axis): axes.append(target.line_axis)
	assert_eq(axes.size(), 2)
	var offer: SkillOffer = _offer(run, &"instant_line_clear")
	var target: SkillTarget = offer.targets[&"instant_line_clear"]
	target.line_axis = 0
	target.line_index = 0
	target.piece_ids = SkillRules.unmarked_material(run.state)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert_true(result.success)
	assert_eq(result.removed.size(), 5)
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_not_null(run.state.rules.state.get_piece(core.piece_id))

func test_changed_targets_and_invalid_trigger_refuse_without_consuming_reward_or_action() -> void:
	var run: RunController = _run()
	var fuse: PieceState = run.state.rules.place_piece(Vector2i.ZERO, 0)
	run.abilities.assign_fuse(fuse.piece_id)
	var offer: SkillOffer = _offer(run, &"instant_color_clear")
	var instance: AbilityInstance = run.state.explosion.instances[fuse.piece_id]
	instance.definition = instance.definition.duplicate(true) as AbilityDefinition
	instance.definition.trigger.trigger_chance = 0.5
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, &"instant_color_clear", 0).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	instance.definition = AbilityResolver.EXPLOSION
	run.state.rules.place_piece(Vector2i(1, 0), 0)
	before = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, &"instant_color_clear", 0).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_command_duplicate_does_not_apply_modifier_twice_and_config_is_stable() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run, &"refill_less")
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = &"refill_less"
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	assert_same(run.execute_command(command), result)
	assert_eq(run.state.spawning.refill_batches[-1], 3)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), RunSnapshot.digest(RunSnapshot.config(_run())))
	assert_string_contains(RunSnapshot.canonical(RunSnapshot.config(run)), "refill_count_effect.gd")
	assert_eq(RunSnapshot.capture(run).spawning.refill_batches["-1"], "3")

func test_frozen_parameter_changes_and_low_event_budget_preserve_whole_choice() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run, &"refill_less")
	run.state.spawning.refill_batches[1] = 3
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, &"refill_less").success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	var piece: PieceState = run.state.rules.place_piece(Vector2i.ZERO, 0)
	run.abilities.assign_fuse(piece.piece_id)
	offer = _offer(run, &"instant_color_clear")
	run.abilities.config = run.abilities.config.duplicate() as ExplosionConfig
	run.abilities.config.event_budget = 1
	before = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, offer.offer_id, &"instant_color_clear", 0).success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_actual_bot_commands_replay_with_expanded_skills_and_reject_old_rule_version() -> void:
	var acquired: Array[StringName] = []
	for seed_value: int in range(12):
		var bot: GreedyBot = GreedyBot.new(seed_value)
		bot.config = bot.config.duplicate(true) as BotConfig
		bot.config.move_limit = 65
		for id: StringName in NEW_IDS: bot.config.skill_weights[id] = 1000.0
		var runner: BotRunner = BotRunner.new()
		var recorder: RunRecorder = runner.play(seed_value + 1, seed_value, bot, false)
		assert_eq(runner.last_replay_error, "")
		for record: Dictionary in recorder.records:
			if record.kind == "SkillAcquired" and NEW_IDS.has(StringName(record.skill_id)) and not acquired.has(StringName(record.skill_id)):
				acquired.append(StringName(record.skill_id))
		var changed: Array[Dictionary] = recorder.records.duplicate(true)
		changed[0].rules_version = "run-commands-v1"
		var replay: RuleReplay = RuleReplay.new()
		assert_false(replay.replay(changed))
		assert_eq(replay.error, "record_version_mismatch")
	assert_gte(acquired.size(), 3, "实际对局至少选择三类新技能，且逐检查点回放一致")
