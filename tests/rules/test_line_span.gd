extends GutTest

const ROW: SkillDefinition = preload("res://gameplay/progression/content/line_row_span.tres")
const COLUMN: SkillDefinition = preload("res://gameplay/progression/content/line_column_span.tres")

func _run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 75)

func _install(run: RunController, skill: SkillDefinition) -> CommandResult:
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
	return run.execute_command(command)

func test_span_cards_require_their_own_supply_and_cap_at_one_level() -> void:
	var run: RunController = _run()
	assert_false(SkillRules.rejection(run.state, ROW, run.abilities.config).is_empty())
	run.state.line_clear.row_unlocked = true
	assert_eq(SkillRules.rejection(run.state, ROW, run.abilities.config), "")
	assert_false(SkillRules.rejection(run.state, COLUMN, run.abilities.config).is_empty())
	var config: String = RunSnapshot.digest(RunSnapshot.config(run))
	assert_true(_install(run, ROW).accepted)
	assert_eq(run.state.skill_instances[ROW.skill_id].level, 1)
	assert_eq(LineClearRules.radius(run.state.line_clear, 0), 1)
	assert_eq(LineClearRules.radius(run.state.line_clear, 1), 0)
	assert_eq(SkillRules.rejection(run.state, ROW, run.abilities.config), "已满级")
	run.state.line_clear.column_unlocked = true
	assert_true(_install(run, COLUMN).accepted)
	assert_eq(LineClearRules.radius(run.state.line_clear, 1), 1)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config)
	assert_eq(_run().state.line_clear.upgrades.size(), 0)

func test_three_rows_and_columns_score_the_actual_union_once() -> void:
	for axis: int in [0, 1]:
		var run: RunController = _run()
		run.state.line_clear.upgrades[LineClearRules.upgrade_for_axis(axis)] = 1
		var source: PieceState = run.abilities.add_line_piece(axis, Vector2i(4, 4), 0)
		for band: int in [3, 4, 5]:
			for index: int in [0, 1]:
				run.state.rules.place_piece(Vector2i(index, band) if axis == 0 else Vector2i(band, index), (band + index) % 5)
		var survivor: PieceState = run.state.rules.place_piece(Vector2i(0, 2) if axis == 0 else Vector2i(2, 0), 2)
		var special: PieceState = run.abilities.add_line_piece(1 - axis, Vector2i(3, 3), 1)
		var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"consume")
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 7)
		assert_eq(results[0].radius, 1)
		assert_eq(results[0].score_entry.final_score, 84)
		assert_eq(run.state.ledger.total, 84)
		assert_not_null(run.state.rules.state.get_piece(survivor.piece_id))
		assert_null(run.state.rules.state.get_piece(special.piece_id))
		assert_eq(results[1].source_id, special.piece_id)

func test_edges_clip_symmetrically_without_shifting_to_a_third_line() -> void:
	for axis: int in [0, 1]:
		for location: int in [0, 4, 8]:
			var run: RunController = _run()
			run.state.line_clear.upgrades[LineClearRules.upgrade_for_axis(axis)] = 1
			var center: Vector2i = Vector2i(4, location) if axis == 0 else Vector2i(location, 4)
			var source: PieceState = run.abilities.add_line_piece(axis, center, 0)
			for band: int in range(9):
				run.state.rules.place_piece(Vector2i(0, band) if axis == 0 else Vector2i(band, 0), band % 5)
			var result: MatchResult = run.abilities.resolve_removal([source], &"match")[0]
			assert_eq(result.removed.size(), 3 if location == 4 else 2)
			for piece: PieceState in result.removed:
				assert_lte(absi((piece.coordinate.y if axis == 0 else piece.coordinate.x) - location), 1)
			assert_eq(run.state.rules.state.get_piece_count(), 9 - result.removed.size())

func test_five_match_departure_uses_the_same_span_without_an_extra_action() -> void:
	var run: RunController = _run()
	run.state.line_clear.upgrades[ROW.skill_id] = 1
	run.abilities.add_line_piece(0, Vector2i(4, 4), 0)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 4), 0)
	for y: int in [3, 5]:
		for x: int in [0, 1]: run.state.rules.place_piece(Vector2i(x, y), x + 1)
	var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
	assert_eq(results.size(), 2)
	assert_eq(results[1].cause, &"line_clear")
	assert_eq(results[1].removed.size(), 4)
	assert_eq(run.state.ledger.total, 50 + 36)
	assert_eq(run.state.activations, 0)
	assert_eq(run.state.spawn_history.size(), 0)

func test_fuses_on_adjacent_band_chain_and_overlapping_sources_dedupe() -> void:
	var run: RunController = _run()
	run.state.line_clear.upgrades[ROW.skill_id] = 1
	var first: PieceState = run.abilities.add_line_piece(0, Vector2i(4, 4), 0)
	var second: PieceState = run.abilities.add_line_piece(0, Vector2i(5, 4), 1)
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(0, 3), 1)
	run.abilities.assign_fuse(fuse.piece_id)
	run.abilities.upgrade_reward()
	run.state.rules.place_piece(Vector2i(0, 2), 2)
	var results: Array[MatchResult] = run.abilities.resolve_removal([second, first], &"skill_clear")
	assert_eq(results.size(), 3)
	assert_eq(results[0].removed.size(), 1)
	assert_eq(results[1].removed.size(), 0)
	assert_eq(results[2].cause, &"explosion")
	assert_eq(results[2].generation, 2)
	assert_eq(run.state.ledger.total, 6 + 5)

func test_wide_fixture_active_command_file_replay_preserves_radius_and_scores() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line_span")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", true)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(0, 3))
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted, result.reason)
	assert_eq(result.turn.matches[0].removed.size(), 3)
	assert_eq(result.turn.matches[0].score_entry.final_score, 24)
	assert_eq(run.state.activations, 1)
	assert_eq(RunRecorder.matches(result.turn.matches)[0].radius, "1")
	for attempt: int in range(5):
		if run.state.phase == RunState.Phase.INPUT or run.state.is_game_over: break
		run.advance()
	assert_eq(run.state.spawn_history.size(), 3)
	run.recorder.finish(run, "abandoned", "span_fixture")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))

func test_greedy_bot_accounts_for_adjacent_bands_without_changing_game_random() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line_span")
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var bot: GreedyBot = GreedyBot.new(7)
	var command: RunCommand = bot.choose(run)
	assert_true(command is ActivateLineCommand)
	assert_gt(bot.last_legal_count, 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
