extends GutTest

const CROSS: SkillDefinition = preload("res://gameplay/progression/content/line_cross_upgrade.tres")

func _run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 101)

func test_cross_requires_either_supply_installs_once_and_is_run_local() -> void:
	var run: RunController = _run()
	assert_false(SkillRules.rejection(run.state, CROSS, run.abilities.config).is_empty())
	run.state.line_clear.column_unlocked = true
	assert_eq(SkillRules.rejection(run.state, CROSS, run.abilities.config), "")
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 1
	offer.choices = [CROSS]
	offer.targets[CROSS.skill_id] = SkillRules.freeze_target(run.state, CROSS)
	run.state.rewards.active_offer = offer
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, 0)
	command.offer_id = 1
	command.reward_id = 1
	command.skill_id = CROSS.skill_id
	var config: String = RunSnapshot.digest(RunSnapshot.config(run))
	assert_true(run.execute_command(command).accepted)
	assert_eq(run.state.skill_instances[CROSS.skill_id].level, 1)
	assert_eq(LineClearRules.cross_radius(run.state.line_clear, 0), 0)
	assert_eq(LineClearRules.cross_radius(run.state.line_clear, 1), 0)
	assert_eq(SkillRules.rejection(run.state, CROSS, run.abilities.config), "已满级")
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config)
	assert_eq(LineClearRules.cross_radius(_run().state.line_clear, 0), -1)

func test_both_source_types_use_independent_spans_and_score_union_once() -> void:
	for axis: int in [0, 1]:
		for levels: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]:
			var run: RunController = _run()
			run.state.line_clear.upgrades[CROSS.skill_id] = 1
			run.state.line_clear.upgrades[&"line_row_span"] = levels.x
			run.state.line_clear.upgrades[&"line_column_span"] = levels.y
			var source: PieceState = run.abilities.add_line_piece(axis, Vector2i(4, 4), 0)
			for x: int in range(9):
				for y: int in range(9):
					if Vector2i(x, y) != source.coordinate: run.state.rules.place_piece(Vector2i(x, y), (x + 2 * y) % 5)
			var request: BlastRequest = (AbilityResolver.LINE_SWEEP.effect as LineSweepEffect).build_request(run.state.rules.state, source, LineClearRules.radius(run.state.line_clear, axis), LineClearRules.cross_radius(run.state.line_clear, axis))
			assert_false(request.target_ids.has(source.piece_id))
			var rows: int = 1 + 2 * levels.x
			var columns: int = 1 + 2 * levels.y
			var count: int = rows * 9 + columns * 9 - rows * columns - 1
			assert_eq(request.target_ids.size(), count)
			var result: MatchResult = run.abilities.resolve_removal([source], &"consume")[0]
			assert_eq(result.removed.size(), count)
			assert_eq(result.radius, levels.x if axis == 0 else levels.y)
			assert_eq(result.cross_radius, levels.y if axis == 0 else levels.x)
			assert_eq(result.score_entry.final_score, count * (count + 5))

func test_corner_cross_clips_each_band_and_dedupes_overlap() -> void:
	var run: RunController = _run()
	run.state.line_clear.upgrades = {CROSS.skill_id: 1, &"line_row_span": 1, &"line_column_span": 1}
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	for x: int in range(9):
		for y: int in range(9):
			if Vector2i(x, y) != Vector2i.ZERO: run.state.rules.place_piece(Vector2i(x, y), (x + y) % 5)
	var result: MatchResult = run.abilities.resolve_removal([source], &"match")[0]
	assert_eq(result.removed.size(), 2 * 9 + 2 * 9 - 4 - 1)
	assert_not_null(run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(Vector2i(2, 2))))

func test_single_axis_can_chain_row_column_core_without_cross_and_without_cycles() -> void:
	var run: RunController = _run()
	var row: PieceState = run.abilities.add_line_piece(0, Vector2i(0, 4), 0)
	var column: PieceState = run.abilities.add_line_piece(1, Vector2i(6, 4), 1)
	var row2: PieceState = run.abilities.add_line_piece(0, Vector2i(6, 7), 2)
	var core: PieceState = run.abilities.add_core(Vector2i(8, 7), 3)
	run.abilities.upgrade_reward()
	run.state.rules.place_piece(Vector2i(7, 6), 4)
	var results: Array[MatchResult] = run.abilities.resolve_removal([row], &"consume")
	assert_eq(results.size(), 4)
	var owners: Array[int] = [row.piece_id, column.piece_id, row2.piece_id, core.piece_id]
	for index: int in range(results.size()):
		assert_eq(results[index].source_id, owners[index])
		assert_eq(results[index].generation, index + 1)
	assert_eq(run.state.ledger.total, 6 + 6 + 6 + 5)
	assert_eq(run.state.line_clear.instances.size(), 0)
	assert_eq(run.state.explosion.instances.size(), 0)
	var traces: Array[Dictionary] = run.state.ability_events.take_traces()
	assert_eq(traces.size(), 4)
	for index: int in range(1, traces.size()): assert_eq(traces[index].parent_event_id, traces[index - 1].event_id)
	assert_eq(run.abilities.resolve_removal([row, column, row2, core], &"consume").size(), 0)

func test_cross_chain_fixture_active_action_and_file_replay_preserve_causal_records() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line_cross")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", true)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(2, 4))
	var outcome: CommandResult = run.execute_command(command)
	assert_true(outcome.accepted, outcome.reason)
	assert_eq(outcome.turn.matches.size(), 4)
	assert_eq(outcome.turn.matches[0].radius, 1)
	assert_eq(outcome.turn.matches[0].cross_radius, 0)
	assert_eq(outcome.turn.matches[1].radius, 0)
	assert_eq(outcome.turn.matches[1].cross_radius, 1)
	assert_eq(RunRecorder.matches(outcome.turn.matches)[0].cross_radius, "0")
	assert_eq(run.state.ledger.total, 35)
	assert_eq(run.state.activations, 1)
	for attempt: int in range(5):
		if run.state.phase == RunState.Phase.INPUT or run.state.is_game_over: break
		run.advance()
	assert_eq(run.state.spawn_history.size(), 3)
	run.recorder.finish(run, "abandoned", "cross_chain_fixture")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(run)))

func test_cross_budget_rejects_before_board_score_and_rng_commit() -> void:
	var run: RunController = _run()
	run.initialize("fixture_line_cross")
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 4
	run.abilities.config = config
	var before: Dictionary = RunSnapshot.capture(run)
	before.erase("last_command")
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(2, 4))
	assert_string_contains(run.execute_command(command).reason, "budget")
	var after: Dictionary = RunSnapshot.capture(run)
	after.erase("last_command")
	assert_eq(RunSnapshot.digest(after), RunSnapshot.digest(before))
