extends GutTest

func test_initialization_adds_five_and_ordinary_batch_still_adds_three() -> void:
	var run: RunController = _new_run(9, 9, 7)
	var initial: RunStepResult = run.initialize()
	assert_eq(initial.spawns.size(), 5)
	assert_eq(run.state.rules.state.get_piece_count(), 5)
	assert_eq(run.state.phase, RunState.Phase.INPUT)
	assert_eq(run.state.turn_count, 1)
	assert_eq(run.state.valid_moves, 0)
	assert_eq(run.spawn_batch().size(), 3)
	assert_eq(run.state.spawn_history.size(), 8)
	var repeated: RunController = _new_run(9, 9, 7)
	var repeated_initial: RunStepResult = repeated.initialize()
	for index: int in range(initial.spawns.size()):
		assert_eq(initial.spawns[index].piece.coordinate, repeated_initial.spawns[index].piece.coordinate)
		assert_eq(initial.spawns[index].piece.match_color, repeated_initial.spawns[index].piece.match_color)

func test_move_commits_match_before_any_presentation() -> void:
	var run: RunController = _new_run(9, 9)
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 0), 0)
	var piece: PieceState = run.state.rules.place_piece(Vector2i(4, 1), 0)
	run.start_turn()
	var result: TurnResult = run.move_piece(piece.piece_id, Vector2i(4, 0))
	assert_true(result.move.is_valid())
	assert_true(result.direct_match)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(result.matches[0].removed.size(), 5)
	assert_eq(result.matches[0].score_entry.root_action_id, 1)
	assert_eq(result.matches[0].score_entry.target_ids.size(), 5)
	assert_true(run.should_spawn(result.direct_match))

func test_invalid_and_busy_move_preserve_run_and_random() -> void:
	var run: RunController = _new_run(9, 9)
	var piece: PieceState = run.state.rules.place_piece(Vector2i.ZERO, 0)
	run.state.rules.place_piece(Vector2i(1, 0), 1)
	run.state.rules.place_piece(Vector2i(0, 1), 2)
	run.start_turn()
	var random_state: int = run.state.random.state
	assert_false(run.move_piece(piece.piece_id, Vector2i(2, 2)).move.is_valid())
	assert_eq(run.state.phase, RunState.Phase.INPUT)
	assert_eq(run.state.turn_count, 1)
	assert_eq(run.state.action_id, 0)
	assert_eq(run.state.random.state, random_state)
	run.enter_rewards()
	assert_eq(run.move_piece(piece.piece_id, Vector2i(2, 2)).move.failure, BoardMoveResult.Failure.BUSY)

func test_full_clear_sampling_uses_current_board_after_reward() -> void:
	var run: RunController = _new_run(9, 9)
	assert_true(run.should_spawn(true))
	run.state.rules.place_piece(Vector2i.ZERO, 0, &"prism_tower")
	assert_false(run.should_spawn(true))
	assert_true(run.should_spawn(false))
	run.state.ledger.commit(0, 1.0, 20)
	assert_true(run.should_spawn(false))

func test_two_spaces_fill_then_third_spawn_fails() -> void:
	var run: RunController = _new_run(2, 1)
	var results: Array[SpawnResult] = run.spawn_batch()
	assert_eq(results.size(), 2)
	assert_true(run.state.is_game_over)
	assert_eq(run.state.phase, RunState.Phase.FINISHED)
	assert_eq(run.state.spawn_history.size(), 2)

func test_three_spaces_fill_then_final_space_check_fails() -> void:
	var run: RunController = _new_run(3, 1)
	assert_eq(run.spawn_batch().size(), 3)
	assert_true(run.state.is_game_over)

func test_first_birth_match_does_not_stop_remaining_births() -> void:
	var run: RunController = _new_run(5, 1)
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 0), 0)
	_seed_first_color(run, 0)
	var results: Array[SpawnResult] = run.spawn_batch()
	assert_eq(results.size(), 3)
	assert_eq(results[0].matches.size(), 1)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.rules.state.get_piece_count(), 2)
	assert_false(run.state.is_game_over)

func test_third_birth_match_is_resolved_before_failure() -> void:
	var selected: RunController = null
	for run_seed: int in range(1000):
		var candidate: RunController = _new_run(5, 3, run_seed)
		for x: int in range(5):
			for y: int in range(3):
				if x == 4:
					continue
				candidate.state.rules.place_piece(Vector2i(x, y), 0 if y == 0 else (x + 2 * y) % 5)
		var results: Array[SpawnResult] = candidate.spawn_batch()
		if results.size() == 3 and not results[2].matches.is_empty():
			selected = candidate
			break
	assert_not_null(selected)
	if selected != null:
		assert_false(selected.state.is_game_over)
		assert_gt(selected.state.rules.state.get_empty_coordinates().size(), 0)

func test_independent_events_and_intersection_use_correct_counts() -> void:
	var run: RunController = _new_run(9, 9)
	for x: int in range(5):
		run.state.rules.place_piece(Vector2i(x, 0), 0)
		run.state.rules.place_piece(Vector2i(x, 4), 1)
	assert_eq(run.resolve_all_matches().size(), 2)
	assert_eq(run.state.ledger.total, 100)
	assert_eq(run.resolve_all_matches().size(), 0)
	assert_eq(run.state.ledger.total, 100)
	var crossed: RunController = _new_run(9, 9)
	for n: int in range(5):
		crossed.state.rules.place_piece(Vector2i(n, 2), 0)
		if n != 2:
			crossed.state.rules.place_piece(Vector2i(2, n), 0)
	assert_eq(crossed.resolve_all_matches()[0].removed.size(), 9)
	assert_eq(crossed.state.ledger.total, 126)

func test_same_seed_and_replacement_run_are_isolated() -> void:
	var first: RunController = _new_run(9, 9, 24)
	var second: RunController = _new_run(9, 9, 24)
	var a: Array[SpawnResult] = first.spawn_batch()
	var b: Array[SpawnResult] = second.spawn_batch()
	for index: int in range(3):
		assert_eq(a[index].piece.coordinate, b[index].piece.coordinate)
		assert_eq(a[index].piece.match_color, b[index].piece.match_color)
	first.state.ledger.commit(0, 1.0, 20)
	first.state.pending_rewards = 2
	assert_eq(second.state.ledger.total, 0)
	assert_eq(second.state.pending_rewards, 0)
	first.state.reset_counters()
	assert_eq(first.state.ledger.total, 0)
	assert_eq(first.state.pending_rewards, 0)
	assert_eq(first.state.spawn_history.size(), 0)

func _new_run(columns: int, rows: int, run_seed: int = 0) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(columns, rows), 5), run_seed)

func _seed_first_color(run: RunController, color: int) -> void:
	for run_seed: int in range(1000):
		run.state.spawning.content_random.seed = run_seed
		if run.state.spawning.draw_color(run.state.spawning.content_random) == color:
			run.state.spawning.content_random.seed = run_seed
			return
	fail_test("未找到固定颜色种子")
