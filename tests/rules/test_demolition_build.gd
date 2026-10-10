extends GutTest

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 77)
	run.state.phase = RunState.Phase.INPUT
	return run

func _skill(id: StringName) -> SkillDefinition:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id == id: return skill
	return null

func _detonate(run: RunController, id: int) -> CommandResult:
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = id
	return run.execute_command(command)

func _install(run: RunController, key: StringName, value: int = 1) -> void:
	run.state.explosion.upgrades[key] = value

func test_catalog_has_39_real_distinct_effects_and_five_grades() -> void:
	var ids: Array[StringName] = []
	var grades: Array[int] = [0, 0, 0, 0, 0]
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		assert_false(ids.has(skill.skill_id))
		ids.append(skill.skill_id)
		grades[skill.rarity] += 1
		var run: RunController = _run()
		run.state.explosion.core_pool_unlocked = skill.skill_id != &"core_drop"
		run.state.explosion.fuse_unlocked = true
		run.state.rewards.acquired[&"core_manual_detonation"] = 1
		run.state.rewards.acquired[&"fuse_relay"] = 1
		run.state.rewards.acquired[&"match_dye_echo"] = 1
		run.state.rewards.consumed_count = 5
		for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 1), x)
		run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i.ZERO + Vector2i.DOWN))
		assert_eq(SkillRules.rejection(run.state, skill, run.abilities.config), "", String(skill.skill_id))
		var offer: SkillOffer = SkillOffer.new()
		offer.offer_id = 1
		offer.reward_id = 6
		offer.choices = [skill]
		var target: SkillTarget = SkillTarget.new()
		if skill.choice_effect != null: target = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
		elif skill.action == SkillDefinition.Action.CORE_DROP: target.coordinate = Vector2i(4, 4)
		elif skill.action in [SkillDefinition.Action.THIN, SkillDefinition.Action.ASSIGN_FUSE]: target.piece_ids = [run.state.rules.state.get_piece_id(Vector2i(1, 1))]
		offer.targets[skill.skill_id] = target
		run.state.rewards.active_offer = offer
		run.state.pending_rewards = 1
		run.enter_rewards()
		var result: SkillApplyResult = SkillRules.apply(run, 1, skill.skill_id, 1 if skill.choice_effect != null and skill.choice_effect.requires_color_choice() else -1)
		assert_true(result.success, "%s: %s" % [skill.skill_id, result.error])
		if skill.choice_effect is InstallUpgradeEffect: assert_eq(SkillRules.level(run.state, skill), 1)
	assert_eq(ids.size(), 39)
	assert_eq(grades, [11, 11, 11, 5, 1])

func test_prerequisites_and_rarity_multiply_after_clamp_once() -> void:
	var run: RunController = _run()
	assert_false(SkillRules.rejection(run.state, _skill(&"core_radius"), run.abilities.config).is_empty())
	run.state.explosion.core_pool_unlocked = true
	assert_eq(SkillRules.rejection(run.state, _skill(&"core_radius"), run.abilities.config), "")
	assert_false(SkillRules.rejection(run.state, _skill(&"fuse_capacity"), run.abilities.config).is_empty())
	run.state.explosion.fuse_unlocked = true
	assert_eq(SkillRules.rejection(run.state, _skill(&"fuse_capacity"), run.abilities.config), "")
	_install(run, &"core_supply_up", 2)
	assert_false(SkillRules.rejection(run.state, _skill(&"core_supply_up"), run.abilities.config).is_empty())
	var profile: Dictionary[StringName, float] = {&"exp": 100.0, &"extra": 100.0}
	assert_almost_eq(SkillOfferGenerator.weight(run.state, _skill(&"blast_aftershock"), profile), 10.0 * 4.0 * 0.06, 0.00001)

func test_active_core_consumes_once_and_normal_refill_still_happens() -> void:
	var run: RunController = _run()
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(_detonate(run, core.piece_id).accepted)
	assert_eq(run.state.action_id, 0)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	_install(run, &"core_manual_detonation")
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = core.piece_id
	var decoded: DetonateCoreCommand = CommandCodec.decode(CommandCodec.encode(command)) as DetonateCoreCommand
	assert_eq(decoded.piece_id, core.piece_id)
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	assert_null(result.turn.move)
	assert_eq(result.turn.removed.size(), 1)
	assert_eq(run.state.ledger.total, 0)
	assert_same(run.execute_command(command), result)
	assert_eq(run.state.activations, 1)
	assert_eq(run.advance().kind, &"end_turn")
	assert_eq(run.advance().spawns.size(), 3)
	assert_eq(run.advance().kind, &"input")
	assert_ne(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_active_budget_failure_preserves_source_score_and_rng() -> void:
	var run: RunController = _run()
	_install(run, &"core_manual_detonation")
	_install(run, &"core_fuse_payload")
	var core: PieceState = run.abilities.add_core(Vector2i(2, 2))
	run.state.rules.place_piece(Vector2i(3, 2), 0)
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities = AbilityResolver.new(run.state, config)
	var pieces: String = RunSnapshot.canonical(run.state.rules.state.get_snapshot().map(func(piece: PieceState) -> Dictionary: return RunSnapshot.piece(piece)))
	var random: int = run.state.random.state
	assert_false(_detonate(run, core.piece_id).accepted)
	assert_eq(run.state.rules.state.get_piece_count(), 2)
	assert_eq(run.state.random.state, random)
	assert_eq(run.state.action_id, 0)
	assert_eq(run.state.ledger.total, 0)
	assert_eq(RunSnapshot.canonical(run.state.rules.state.get_snapshot().map(func(piece: PieceState) -> Dictionary: return RunSnapshot.piece(piece))), pieces)

func test_payload_creates_immediate_chain_and_score_is_extra_only() -> void:
	var run: RunController = _run()
	_install(run, &"core_manual_detonation")
	_install(run, &"core_fuse_payload")
	_install(run, &"marked_reward")
	_install(run, &"chain_reward")
	_install(run, &"blast_chain_bonus")
	run.state.explosion.multiplier_level = 20
	var core: PieceState = run.abilities.add_core(Vector2i(2, 2))
	run.state.rules.place_piece(Vector2i(3, 2), 0)
	run.state.rules.place_piece(Vector2i(4, 2), 2)
	var outcome: CommandResult = _detonate(run, core.piece_id)
	assert_true(outcome.accepted)
	assert_eq(outcome.turn.matches.size(), 3)
	assert_eq(outcome.turn.matches[0].score_entry.extra_score, 5)
	assert_eq(outcome.turn.matches[1].score_entry.extra_score, 10)
	assert_eq(outcome.turn.matches[2].score_entry.extra_score, 0)
	for result: MatchResult in outcome.turn.matches: assert_eq(result.score_entry.base_score, 0)
	var rewards: Array[MatchResult] = DemolitionRules.settle(run.state, run.turn_action_id)
	assert_eq(rewards.size(), 1)
	assert_eq(rewards[0].score_entry.extra_score, 10)
	assert_true(DemolitionRules.settle(run.state, run.turn_action_id).is_empty())

func test_relay_snapshot_does_not_propagate_new_source_same_turn() -> void:
	var run: RunController = _run()
	_install(run, &"fuse_relay")
	var source: PieceState = run.state.rules.place_piece(Vector2i(0, 0), 0)
	run.abilities.assign_fuse(source.piece_id)
	var next: PieceState = run.state.rules.place_piece(Vector2i(1, 0), 2)
	var later: PieceState = run.state.rules.place_piece(Vector2i(2, 0), 3)
	assert_eq(DemolitionRules.relay(run.abilities), [next.piece_id])
	assert_false(run.state.explosion.instances.has(later.piece_id))
	assert_eq(DemolitionRules.relay(run.abilities), [later.piece_id])

func test_aftershock_once_selective_filter_and_radius_caps() -> void:
	var run: RunController = _run()
	_install(run, &"core_manual_detonation")
	_install(run, &"blast_aftershock")
	_install(run, &"selective_blast")
	_install(run, &"core_radius")
	run.state.explosion.radius_level = 1
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var same: PieceState = run.state.rules.place_piece(Vector2i(5, 4), 1)
	run.state.rules.place_piece(Vector2i(4, 5), 0)
	var result: CommandResult = _detonate(run, core.piece_id)
	assert_eq(result.turn.matches.size(), 2)
	assert_eq(result.turn.matches[0].radius, 3)
	assert_eq(result.turn.matches[1].radius, 1)
	assert_eq(result.turn.matches[1].score_entry.ability_id, &"blast_aftershock")
	assert_not_null(run.state.rules.state.get_piece(same.piece_id))
	assert_true(run.state.explosion.actions[run.turn_action_id].aftershock_used)

func test_relief_waits_for_complete_root_and_extends_without_double_strength() -> void:
	var run: RunController = _run()
	_install(run, &"core_manual_detonation")
	_install(run, &"blast_refill_relief")
	run.state.explosion.radius_level = 1
	run.state.spawning.extend_refill(-1, 3)
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	for x: int in range(3, 6):
		for y: int in range(3, 6):
			if Vector2i(x, y) != core.coordinate: run.state.rules.place_piece(Vector2i(x, y), 0)
	assert_true(_detonate(run, core.piece_id).accepted)
	assert_eq(run.state.spawning.refill_batches[-1], 3)
	run.advance()
	assert_eq(run.advance().spawns.size(), 2)
	assert_eq(run.state.spawning.refill_batches[-1], 3)
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 2)
	assert_true(run.state.explosion.actions.is_empty())

func test_supply_uses_normal_slots_unique_and_run_state_isolated() -> void:
	var run: RunController = _run()
	var other: RunController = _run()
	run.state.explosion.core_pool_unlocked = true
	_install(run, &"core_supply_up", 2)
	var spawned: int = 0
	var cores: int = 0
	for index: int in range(200):
		var result: SpawnResult = run.spawn_one()
		spawned += 1
		if result.piece.content_id == &"special_demolition": cores += 1
		for piece: PieceState in run.state.rules.state.get_snapshot():
			run.state.rules.remove_piece(piece.piece_id)
			run.state.explosion.instances.erase(piece.piece_id)
	assert_eq(spawned, 200)
	assert_gt(cores, 0)
	assert_false(other.state.explosion.core_pool_unlocked)
	assert_eq(other.state.explosion.level(&"core_supply_up"), 0)
	assert_eq(DemolitionRules.CONFIG.core_type_weight, 1)

func test_core_drop_new_budget_preflight_preserves_entire_choice() -> void:
	var run: RunController = _run()
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 1)
	_install(run, &"core_fuse_payload")
	_install(run, &"blast_aftershock")
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 3
	run.abilities = AbilityResolver.new(run.state, config)
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 1
	offer.choices = [_skill(&"core_drop")]
	var target: SkillTarget = SkillTarget.new()
	target.coordinate = Vector2i(4, 0)
	offer.targets[&"core_drop"] = target
	run.state.rewards.active_offer = offer
	run.state.pending_rewards = 1
	run.enter_rewards()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(SkillRules.apply(run, 1, &"core_drop").success)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_false(run.state.explosion.core_pool_unlocked)

func test_plant_runs_after_all_match_groups_removed_once_per_root() -> void:
	var run: RunController = _run()
	_install(run, &"fuse_match_plant")
	for x: int in range(5):
		run.state.rules.place_piece(Vector2i(x, 0), 1)
		run.state.rules.place_piece(Vector2i(x, 2), 2)
	var candidate: PieceState = run.state.rules.place_piece(Vector2i(0, 1), 3)
	var other: PieceState = run.state.rules.place_piece(Vector2i(1, 1), 4)
	var results: Array[MatchResult] = run.resolve_all_matches()
	assert_eq(results.size(), 2)
	assert_eq(run.state.rules.state.get_piece_count(), 2)
	assert_true(run.state.explosion.instances.has(candidate.piece_id))
	assert_false(run.state.explosion.instances.has(other.piece_id))
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 3), 0)
	run.resolve_all_matches()
	assert_false(run.state.explosion.instances.has(other.piece_id))

func test_chain_radius_only_later_fuses_and_general_rewards_are_independent() -> void:
	var run: RunController = _run()
	_install(run, &"blast_chain_radius")
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(0, 0), 0)
	assert_eq(DemolitionRules.radius(run.state, core, 2, 1), 1)
	assert_eq(DemolitionRules.radius(run.state, fuse, 1, 1), 1)
	assert_eq(DemolitionRules.radius(run.state, fuse, 2, 1), 2)
	_install(run, &"precision_reward", 2)
	_install(run, &"longline_reward", 2)
	run.state.explosion.match_extra_level = 1
	for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 1), 1)
	for x: int in range(6): run.state.rules.place_piece(Vector2i(x, 3), 2)
	var results: Array[MatchResult] = run.resolve_all_matches()
	assert_eq(results.size(), 2)
	assert_eq(results[0].score_entry.extra_score, 20)
	assert_eq(results[1].score_entry.extra_score, 50)

func test_old_parent_root_survives_interleaved_skill_root() -> void:
	var run: RunController = _run()
	_install(run, &"core_manual_detonation")
	_install(run, &"chain_reward")
	var core: PieceState = run.abilities.add_core(Vector2i(1, 1))
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(2, 1), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.rules.place_piece(Vector2i(3, 1), 2)
	assert_true(_detonate(run, core.piece_id).accepted)
	var parent: int = run.turn_action_id
	assert_eq(run.state.explosion.actions[parent].effective_blasts, 2)
	run.state.action_id += 1
	run.state.rule_action_id = run.state.action_id
	DemolitionRules.action(run.state)
	DemolitionRules.settle(run.state, run.state.rule_action_id)
	assert_true(run.state.explosion.actions.has(parent))
	run.advance()
	var step: RunStepResult = run.advance()
	assert_eq(step.matches.size(), 1)
	assert_eq(step.matches[0].score_entry.root_action_id, parent)
	assert_true(run.state.explosion.actions.is_empty())

func test_active_command_chain_settlement_and_refill_replay_all_checkpoints() -> void:
	var run: RunController = _run()
	run.initialize("fixture_demolition")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", false)
	var command: RunCommand = GreedyBot.new().choose(run)
	assert_true(command is DetonateCoreCommand)
	assert_true(run.execute_command(command).accepted)
	for stage: int in range(6):
		var step: RunStepResult = run.advance()
		if step.kind == &"input": break
		assert_ne(step.kind, &"error")
		assert_ne(step.kind, &"offer")
	run.recorder.finish(run, "abandoned", "fixture_end")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))

func test_rarity_styles_are_owned_by_each_card() -> void:
	var a: Button = Button.new()
	var b: Button = Button.new()
	SkillRarity.style(a, SkillDefinition.Rarity.LEGENDARY)
	SkillRarity.style(b, SkillDefinition.Rarity.RARE)
	var style_a: StyleBoxFlat = a.get_theme_stylebox("normal") as StyleBoxFlat
	var style_b: StyleBoxFlat = b.get_theme_stylebox("normal") as StyleBoxFlat
	style_a.border_color = Color.RED
	assert_eq(style_b.border_color, Color(SkillRarity.COLORS[SkillDefinition.Rarity.RARE], 0.65))
	assert_eq(SkillRarity.COLORS[SkillDefinition.Rarity.LEGENDARY], Color("ffae57"))
	a.free()
	b.free()
