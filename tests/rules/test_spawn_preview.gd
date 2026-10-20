extends GutTest

func _run(seed_value: int = 17) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)

func test_preview_matches_actual_births_and_only_actual_consumption_advances() -> void:
	var run: RunController = _run()
	run.initialize()
	var preview: Array[SpawnToken] = run.state.spawning.preview(3)
	assert_eq(preview.size(), 3)
	var births: Array[SpawnResult] = run.spawn_batch()
	for index: int in range(3): assert_eq(births[index].piece.match_color, preview[index].color)
	assert_eq(run.state.spawning.preview(3).size(), 0)
	run.start_turn()
	assert_eq(run.state.spawning.preview(3).size(), 3)

func test_direct_match_without_full_clear_preserves_plan_and_temporary_batches() -> void:
	var run: RunController = _run()
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 0)
	var piece: PieceState = run.state.rules.place_piece(Vector2i(4, 1), 0)
	run.state.rules.place_piece(Vector2i(8, 8), 1)
	run.state.spawning.extend_refill(-1, 3)
	run.start_turn()
	var before: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = piece.piece_id
	command.target = Vector2i(4, 0)
	assert_true(run.execute_command(command).accepted)
	run.advance()
	assert_eq(run.advance().spawns.size(), 0)
	run.advance()
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), before)
	assert_eq(run.state.spawning.refill_batches[-1], 3)

func test_count_changes_preserve_prefix_and_weights_only_affect_appended_tokens() -> void:
	var run: RunController = _run()
	run.start_turn()
	var before: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	run.state.spawning.color_weights = [20, 1, 1, 1, 1]
	var expected_random: RandomNumberGenerator = RandomNumberGenerator.new()
	expected_random.state = run.state.spawning.content_random.state
	var expected: int = run.state.spawning.draw_color(expected_random)
	run.state.spawning.extend_refill(1, 3)
	run.prepare_spawn_plan()
	assert_eq(run.state.spawning.preview(4)[3].color, expected)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data().slice(0, 3)), before)
	run.state.spawning.extend_refill(-1, 3)
	assert_eq(run.state.spawning.next_refill_count(RunController.SPAWN_CONFIG), 3)
	assert_eq(run.state.spawning.preview(3).size(), 3)
	var remaining: int = run.state.spawning.preview(4)[3].color
	run.spawn_batch(3)
	assert_eq(run.state.spawning.preview(3)[0].color, remaining)

func test_position_random_read_only_preview_and_copies_cannot_change_content_plan() -> void:
	var run: RunController = _run()
	var other: RunController = _run()
	run.start_turn()
	other.start_turn()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	for index: int in range(30): run.state.spawning.preview(3)[0].color = 4
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	for index: int in range(15): run.state.random.randf()
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), RunSnapshot.canonical(other.state.spawning.plan_data()))
	run.state.reset_counters()
	run.start_turn()
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), RunSnapshot.canonical(other.state.spawning.plan_data()))

func test_core_candidates_have_locked_fallback_and_actual_unique_constraint() -> void:
	var selected: RunController = null
	for seed_value: int in range(500):
		var run: RunController = _run(seed_value)
		run.state.explosion.core_pool_unlocked = true
		run.prepare_spawn_plan()
		if run.state.spawning.preview(1)[0].core_candidate:
			selected = run
			break
	assert_not_null(selected)
	if selected == null: return
	var token: SpawnToken = selected.state.spawning.preview(1)[0]
	selected.abilities.add_core(Vector2i(4, 4))
	var result: SpawnResult = selected.spawn_one()
	assert_eq(result.piece.content_id, &"")
	assert_eq(result.piece.match_color, token.color)
	var matching: RunController = _run(selected.state.random.seed)
	matching.state.explosion.core_pool_unlocked = true
	matching.prepare_spawn_plan()
	assert_eq(matching.spawn_one().piece.content_id, &"special_demolition")

func test_full_board_does_not_consume_pending_token() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(1, 1), 5), 7)
	run.prepare_spawn_plan()
	var before: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	run.state.rules.place_piece(Vector2i.ZERO, 1)
	assert_null(run.spawn_one())
	assert_true(run.state.is_game_over)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), before)

func test_core_birth_uses_all_five_preview_colors_and_fallback_stays_locked() -> void:
	var seen: Array[int] = []
	for seed_value: int in range(500):
		var run: RunController = _run(seed_value)
		run.state.explosion.core_pool_unlocked = true
		run.prepare_spawn_plan()
		var token: SpawnToken = run.state.spawning.preview(1)[0]
		if not token.core_candidate or seen.has(token.color): continue
		seen.append(token.color)
		assert_eq(token.core_color, token.color, "记录中的特殊棋颜色也应等于预告")
		var random_before: int = run.state.spawning.content_random.state
		var birth: SpawnResult = run.spawn_one()
		assert_eq(birth.piece.content_id, &"special_demolition")
		assert_eq(birth.piece.match_color, token.color, "实际爆破手颜色必须等于预告")
		assert_true(run.state.explosion.instances.has(birth.piece.piece_id))
		assert_eq(run.state.spawning.content_random.state, random_before)
		var fallback: RunController = _run(seed_value)
		fallback.state.explosion.core_pool_unlocked = true
		fallback.prepare_spawn_plan()
		fallback.abilities.add_core(Vector2i(4, 4))
		var ordinary: SpawnResult = fallback.spawn_one()
		assert_eq(ordinary.piece.content_id, &"")
		assert_eq(ordinary.piece.match_color, token.color)
		if seen.size() == 5: break
	assert_eq(seen.size(), 5)

func test_preview_colored_core_participates_in_same_color_five_match() -> void:
	var seen: Array[int] = []
	for seed_value: int in range(500):
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(5, 1), 5), seed_value)
		run.state.explosion.core_pool_unlocked = true
		run.prepare_spawn_plan()
		var token: SpawnToken = run.state.spawning.preview(1)[0]
		if not token.core_candidate or seen.has(token.color): continue
		seen.append(token.color)
		for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), token.color)
		var birth: SpawnResult = run.spawn_one()
		assert_eq(birth.piece.match_color, token.color)
		assert_false(birth.matches.is_empty(), "预告颜色应参与同色五连")
		assert_gt(run.state.ledger.total, 0)
		if seen.size() == 5: break
	assert_eq(seen.size(), 5)

func test_non_default_core_birth_replays_from_real_commands() -> void:
	var seen: bool = false
	for seed_value: int in range(16):
		var run: RunController = _run(seed_value)
		run.initialize("fixture_demolition")
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "test", false)
		var bot: GreedyBot = GreedyBot.new(seed_value)
		for step: int in range(80):
			if run.state.is_game_over or not run.state.rule_error.is_empty(): break
			if run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null:
				run.advance()
			elif run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS]:
				var command: RunCommand = bot.choose(run)
				if command == null: break
				assert_true(run.execute_command(command).accepted)
			else:
				run.advance()
			for birth: SpawnResult in run.state.spawn_history:
				if birth.piece.content_id == &"special_demolition" and birth.piece.match_color != run.abilities.config.core_color:
					seen = true
			if seen: break
		if not seen: continue
		run.recorder.finish(run, "abandoned", "test_complete")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay(run.recorder.records), replay.error)
		assert_eq(replay.checked_records, run.recorder.records.size())
		break
	assert_true(seen, "正常命令产生非默认颜色爆破手，并精确回放")
