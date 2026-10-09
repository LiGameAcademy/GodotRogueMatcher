extends GutTest

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_dye")
	return run

func _move(run: RunController) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(4, 6))
	command.target = Vector2i(4, 4)
	return run.execute_command(command)

func test_echo_completes_second_line_and_scores_mark_once() -> void:
	var run: RunController = _run()
	var result: CommandResult = _move(run)
	assert_true(result.accepted)
	assert_eq(run.state.ledger.total, 105)
	assert_eq(result.turn.matches.size(), 3)
	assert_eq(result.turn.matches[1].cause, &"dye")
	assert_eq(result.turn.matches[1].previous_colors, [2])
	assert_eq(result.turn.matches[1].recolored[0].match_color, 0)
	assert_eq(run.state.dye.waves_used, 1)
	assert_true(run.state.dye.marks.is_empty())
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_true(result.turn.direct_match)

func test_new_line_allows_second_wave_but_shared_budget_stops_third() -> void:
	var run: RunController = _run()
	run.state.dye.upgrades[&"dye_chain_depth"] = 1
	var extra: PieceState = run.state.rules.place_piece(Vector2i(0, 2), 1)
	var result: CommandResult = _move(run)
	assert_true(result.accepted)
	assert_eq(run.state.dye.waves_used, 2)
	assert_eq(run.state.rules.state.get_piece(extra.piece_id).match_color, 0)
	assert_eq(run.state.ledger.total, 105)
	assert_eq(result.turn.matches.size(), 4)

func test_recolor_preserves_fuse_and_identity_without_direct_score() -> void:
	var run: RunController = _run()
	var piece: PieceState = run.state.rules.place_piece(Vector2i(7, 7), 2)
	assert_true(run.abilities.assign_fuse(piece.piece_id))
	var instance: AbilityInstance = run.state.explosion.instances[piece.piece_id]
	run.state.phase = RunState.Phase.REWARDS
	var results: Array[MatchResult] = DyeRules.recolor(run.abilities, [piece.piece_id], 1)
	assert_eq(results.size(), 1)
	assert_eq(run.state.ledger.total, 0)
	assert_same(run.state.explosion.instances[piece.piece_id], instance)
	assert_eq(run.state.rules.state.get_piece(piece.piece_id).coordinate, Vector2i(7, 7))
	assert_eq(run.state.dye.waves_used, 0)

func test_no_surviving_target_leaves_only_first_match() -> void:
	var run: RunController = _run()
	var id: int = run.state.rules.state.get_piece_id(Vector2i(0, 3))
	run.state.rules.set_piece_color(id, 0)
	# Remove the incomplete neighboring row; only the originating line remains.
	for x: int in range(5): run.state.rules.remove_piece(run.state.rules.state.get_piece_id(Vector2i(x, 3)))
	var result: CommandResult = _move(run)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(result.turn.matches.size(), 1)
	assert_eq(run.state.dye.waves_used, 0)

func test_dye_state_is_owned_per_run_and_stale_instant_targets_reject() -> void:
	var a: RunController = _run()
	var b: RunController = _run()
	a.state.dye.upgrades[&"dye_target_up"] = 1
	assert_eq(b.state.dye.level(&"dye_target_up"), 0)
	var effect: DyeMaterialEffect = DyeMaterialEffect.new()
	var target: SkillTarget = effect.freeze(SkillRules.effect_context(a.state), a.state.rewards.target_random)
	assert_gt(target.piece_ids.size(), 0)
	a.state.rules.set_piece_color(target.piece_ids[0], target.color)
	var request: ChoiceEffectRequest = effect.build(SkillRules.effect_context(a.state), target)
	assert_false(request.error.is_empty())

func test_fixture_records_replay_rule_and_presentation_events() -> void:
	var run: RunController = _run()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", false)
	assert_true(_move(run).accepted)
	run.recorder.finish(run, "abandoned", "dye_complete")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)
	assert_eq(replay.run.state.ledger.total, 105)

func test_non_match_removal_does_not_consume_later_spawn_match_opportunity() -> void:
	var run: RunController = _run()
	run.state.phase = RunState.Phase.MOVING
	run.state.action_id = 1
	run.state.rule_action_id = 1
	var green: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(Vector2i(8, 8)))
	run.abilities.resolve_removal([green], &"skill_clear")
	assert_false(run.state.dye.considered_match)
	run.state.phase = RunState.Phase.INPUT
	var turn: TurnResult = run.move_piece(run.state.rules.state.get_piece_id(Vector2i(4, 6)), Vector2i(4, 4))
	assert_true(turn.move.is_valid())
	assert_eq(run.state.ledger.total, 105)

func test_dye_bonus_is_not_paid_on_explosion_removal() -> void:
	var run: RunController = _run()
	var green: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(Vector2i(8, 8)))
	run.state.dye.marks[green.piece_id] = 1
	run.abilities.resolve_removal([green], &"explosion")
	assert_eq(run.state.ledger.total, 0)
	assert_false(run.state.dye.marks.has(green.piece_id))

func test_blast_bridge_dyes_surviving_edge_material_and_shares_wave_limit() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.state.phase = RunState.Phase.MOVING
	run.state.action_id = 1
	run.state.rule_action_id = 1
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	run.state.dye.upgrades[&"blast_dye"] = 1
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	run.state.rules.place_piece(Vector2i(4, 5), 0)
	var edge: PieceState = run.state.rules.place_piece(Vector2i(6, 4), 2)
	var results: Array[MatchResult] = run.abilities.resolve_removal([core], &"consume")
	assert_eq(results.size(), 2)
	assert_eq(results[1].cause, &"dye")
	assert_eq(run.state.rules.state.get_piece(edge.piece_id).match_color, core.match_color)
	assert_eq(run.state.dye.waves_used, 1)
	assert_true(run.state.dye.considered_blast)
	assert_eq(run.state.ledger.total, 0)
