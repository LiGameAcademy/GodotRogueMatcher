extends GutTest

const F: Script = preload("res://tests/support/u_template_fixture.gd")
const UNLOCK: Script = preload("res://tests/support/shape_unlock_fixture.gd")

func _move_zs(enabled: bool, far: bool) -> RunController:
	var run: RunController = F.run(enabled)
	F.place(run, F.U.offsets, Vector2i.ZERO, 0, Vector2i(2, 2))
	run.state.rules.place_piece(Vector2i(2, 3), 0)
	if far: run.state.rules.place_piece(Vector2i(8, 8), 1)
	run.start_turn()
	return run

func test_direct_u_move_uses_same_refill_exemption_and_frozen_plan() -> void:
	var run: RunController = _move_zs(true, true)
	run.state.spawning.extend_refill(-1, 3)
	run.prepare_spawn_plan()
	var before: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	var response: CommandResult = F.move(run, run.state.rules.state.get_piece_at(Vector2i(2, 3)), Vector2i(2, 2))
	assert_true(response.accepted)
	assert_true(response.turn.direct_match)
	assert_eq(response.turn.matches[0].match_source, &"direct_move")
	assert_eq(response.turn.matches[0].hits[0].shape_id, &"u")
	assert_eq(run.state.ledger.total, 84)
	run.advance()
	assert_true(run.advance().spawns.is_empty())
	assert_eq(run.state.spawning.refill_batches[-1], 3)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), before)

func test_disabled_u_does_not_match_or_skip_refill_and_full_clear_still_refills() -> void:
	for enabled: bool in [false, true]:
		var run: RunController = _move_zs(enabled, false)
		var response: CommandResult = F.move(run, run.state.rules.state.get_piece_at(Vector2i(2, 3)), Vector2i(2, 2))
		assert_true(response.accepted)
		assert_eq(response.turn.direct_match, enabled)
		run.advance()
		assert_eq(run.advance().spawns.size(), 3)

func test_birth_u_match_finishes_remaining_locked_tokens() -> void:
	var run: RunController = F.run()
	run.prepare_spawn_plan()
	var preview: Array[SpawnToken] = run.state.spawning.preview(3)
	F.place(run, F.U.offsets, Vector2i.ZERO, preview[0].color, Vector2i(2, 2))
	run.state.rules.place_piece(Vector2i(8, 8), (preview[0].color + 1) % 5)
	assert_true(F.next_coordinate(run, Vector2i(2, 2)))
	var births: Array[SpawnResult] = run.spawn_batch(3)
	assert_eq(births.size(), 3)
	assert_eq(births[0].matches.size(), 1)
	assert_eq(births[0].matches[0].removed.size(), 7)
	assert_eq(births[0].matches[0].match_source, &"birth")
	for index: int in range(3): assert_eq(births[index].piece.match_color, preview[index].color)
	assert_eq(run.state.rules.state.get_piece_count(), 3)
	assert_false(run.direct_match())

func test_batch_dye_u_and_straight_line_score_final_union_once() -> void:
	var run: RunController = F.run()
	var changed: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(2, 2)]
	var ids: Array[int] = []
	for coordinate: Vector2i in F.U.offsets:
		var piece: PieceState = run.state.rules.place_piece(coordinate, 1 if changed.has(coordinate) else 0)
		if changed.has(coordinate): ids.append(piece.piece_id)
	for axis: int in [3, 4]: run.state.rules.place_piece(Vector2i(0, axis), 0)
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	var results: Array[MatchResult] = DyeRules.recolor(run.abilities, ids, 0)
	assert_eq(results.size(), 2)
	assert_eq(results[0].recolored.size(), 3)
	assert_eq(results[1].removed.size(), 9)
	assert_eq(results[1].match_source, &"dye")
	assert_eq(run.state.ledger.total, 146)
	assert_false(run.direct_match())

func test_real_u_unlock_immediately_scans_and_does_not_enable_l() -> void:
	var run: RunController = F.unlock_run()
	var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	var response: CommandResult = UNLOCK.choose(run, &"fixture_unlock_u")
	assert_true(response.accepted, response.reason)
	assert_eq(response.skill.matches.size(), 1)
	assert_eq(response.skill.matches[0].hits[0].shape_id, &"u")
	assert_eq(response.skill.matches[0].match_source, &"shape_unlock")
	assert_eq(run.state.ledger.total, 84)
	assert_eq(run.state.rules.shape_unlocks.ids(), [&"u"])
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.spawn_history.size(), 0)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)
	assert_eq(run.state.valid_moves, 0)

func test_real_u_full_clear_uses_one_recovery_and_disk_replays_current_protocol() -> void:
	var run: RunController = F.unlock_run(true)
	UNLOCK.record(run, true)
	var offer: SkillOffer = run.prepare_offer()
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, 0)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = &"fixture_unlock_u"
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	var prefix: Array[Dictionary] = run.recorder.records.duplicate(true)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(prefix), replay.error)
	assert_eq(replay.run.state.rules.shape_unlocks.ids(), [&"u"])
	assert_eq(run.advance().kind, &"recovery")
	assert_eq(replay.run.advance().kind, &"recovery")
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), RunSnapshot.canonical(RunSnapshot.capture(replay.run)))
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), result)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)
	run.recorder.finish(run, "censored", "u_template_slice")
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(replay.checked_records, run.recorder.records.size())
	assert_eq(RunSnapshot.RULES_VERSION, "run-commands-v46-unified-offer-audit")

func test_u_and_l_unlock_orders_keep_independent_identity_and_stable_resources() -> void:
	for u_first: bool in [false, true]:
		var run: RunController = F.run(false)
		var first: MatchShapeTemplate = F.U if u_first else F.L
		var second: MatchShapeTemplate = F.L if u_first else F.U
		assert_true(run.state.rules.shape_unlocks.unlock(first, 1))
		assert_false(run.state.rules.shape_unlocks.contains(second.shape_id))
		assert_true(run.state.rules.shape_unlocks.unlock(second, 2))
		F.place(run, F.U.offsets)
		assert_eq(run.state.rules.find_matches()[0].piece_ids.size(), 7)
		assert_eq(run.state.rules.shape_unlocks.ids(), [&"l", &"u"])
	assert_eq(F.U.offsets.size(), 7)

func test_both_real_unlock_orders_record_the_same_sorted_shape_identities() -> void:
	for u_first: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.U_PROFILE)
		run.initialize("fixture_shape_unlock_u_two_rewards")
		UNLOCK.record(run, true)
		var first: StringName = &"fixture_unlock_u" if u_first else &"fixture_unlock_l"
		var second: StringName = &"fixture_unlock_l" if u_first else &"fixture_unlock_u"
		var first_result: CommandResult = UNLOCK.choose(run, first)
		assert_true(first_result.accepted)
		assert_eq(first_result.skill.matches[0].removed.size(), 7)
		assert_eq(first_result.skill.matches[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"u"), u_first)
		assert_eq(run.advance().kind, &"offer")
		if u_first:
			assert_false(run.prepare_offer().choices.any(func(skill: SkillDefinition) -> bool: return skill.skill_id == &"fixture_unlock_u"))
		var second_result: CommandResult = UNLOCK.choose(run, second)
		assert_true(second_result.accepted)
		assert_true(second_result.skill.matches.is_empty())
		assert_eq(run.advance().kind, &"input")
		assert_eq(run.state.rules.shape_unlocks.ids(), [&"l", &"u"])
		assert_eq(run.state.ledger.total, 84)
		assert_eq(run.state.rewards.consumed_count, 2)
		assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 0)
		run.recorder.finish(run, "censored", "u_template_order")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(run.recorder.path), replay.error)
		assert_eq(replay.run.state.rules.shape_unlocks.ids(), [&"l", &"u"])
func test_fixture_profiles_keep_old_catalog_and_production_separate() -> void:
	var production: RunController = F.run(false)
	var old: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.PROTOTYPE_PROFILE)
	var current: RunController = F.unlock_run()
	assert_false(production.offer_catalog().any(func(skill: SkillDefinition) -> bool: return String(skill.skill_id).begins_with("fixture_")))
	assert_true(old.offer_catalog().any(func(skill: SkillDefinition) -> bool: return skill.skill_id == &"fixture_unlock_t"))
	assert_false(old.offer_catalog().any(func(skill: SkillDefinition) -> bool: return skill.skill_id == &"fixture_unlock_u"))
	assert_true(current.offer_catalog().any(func(skill: SkillDefinition) -> bool: return skill.skill_id == &"fixture_unlock_u"))
	assert_false(current.offer_catalog().any(func(skill: SkillDefinition) -> bool: return skill.skill_id == &"fixture_unlock_t"))
	assert_ne(RunSnapshot.digest(RunSnapshot.config(old)), RunSnapshot.digest(RunSnapshot.config(current)))

func test_unknown_profile_and_cross_profile_initialization_are_rejected() -> void:
	var run: RunController = F.unlock_run()
	UNLOCK.record(run)
	var records: Array[Dictionary] = run.recorder.records.duplicate(true)
	records[0].config.prototype_profile = "shape-unlock-unknown"
	var replay: RuleReplay = RuleReplay.new()
	assert_false(replay.restore_prefix(records))
	assert_eq(replay.error, "invalid_prototype_profile")
	var old: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, RunController.PROTOTYPE_PROFILE)
	old.initialize("fixture_shape_unlock_u")
	assert_eq(old.state.rule_error, "unsupported_initialization")
	assert_eq(old.state.rules.state.get_piece_count(), 0)
