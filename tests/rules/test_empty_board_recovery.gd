extends GutTest

const FIXTURE: Script = preload("res://tests/support/shape_unlock_fixture.gd")

class ClearRecovery extends RunController:
	func spawn_batch(count: int = 3, source: StringName = &"normal", batch_id: int = 0) -> Array[SpawnResult]:
		var results: Array[SpawnResult] = super.spawn_batch(count, source, batch_id)
		if source == &"empty_recovery" and not results.is_empty():
			results.back().matches.append_array(abilities.resolve_removal(state.rules.state.get_snapshot(), &"fixture_clear"))
		return results

class ChainRecovery extends RunController:
	var extra_recovery_score: int = 0
	func spawn_batch(count: int = 3, source: StringName = &"normal", batch_id: int = 0) -> Array[SpawnResult]:
		if source == &"empty_recovery":
			if extra_recovery_score > 0:
				state.ledger.commit(0, 1.0, extra_recovery_score, &"fixture_recovery_score", state.rule_action_id, [])
			# Explicit R07 fixture adds anchors before the first real birth; no production summon rule.
			var color: int = state.spawning.preview(1)[0].color
			for coordinate: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]:
				state.rules.place_piece(coordinate, color)
			abilities.assign_fuse(state.rules.state.get_piece_id(Vector2i(0, 2)))
			var q: PieceState = state.rules.place_piece(Vector2i(0, 3), (color + 1) % 5)
			abilities.assign_fuse(q.piece_id)
			state.rules.place_piece(Vector2i(0, 4), (color + 1) % 5)
			var empty: Array[Vector2i] = state.rules.state.get_empty_coordinates()
			for seed_value: int in range(10000):
				var random: RandomNumberGenerator = RandomNumberGenerator.new()
				random.seed = seed_value
				if empty[random.randi_range(0, empty.size() - 1)] == Vector2i(2, 2):
					state.random.seed = seed_value
					break
		return super.spawn_batch(count, source, batch_id)

func test_recovery_consumes_displayed_tokens_once_without_player_or_stage_action() -> void:
	var run: RunController = FIXTURE.run(true)
	var preview: Array[SpawnToken] = run.state.spawning.preview(3)
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.state.spawn_history.size(), 0, "unlock leaf must not spawn")
	var turn: int = run.state.turn_count
	var step: RunStepResult = run.advance()
	assert_eq(step.kind, &"recovery")
	assert_eq(step.spawns.size(), 3)
	for index: int in range(3):
		assert_eq(step.spawns[index].piece.match_color, preview[index].color)
		assert_eq(step.spawns[index].source, &"empty_recovery")
		assert_eq(step.spawns[index].batch_id, 1)
	assert_eq(run.state.valid_moves, 0)
	assert_eq(run.state.activations, 0)
	assert_eq(run.state.turn_count, turn)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.spawn_history.size(), 3)
	assert_true(run.state.rules.shape_unlocks.contains(&"l"))

func test_recovery_honors_each_finite_modifier_without_consuming_its_batches() -> void:
	for delta: int in [-1, 1, 0]:
		var run: RunController = FIXTURE.run(true)
		if delta <= 0: run.state.spawning.extend_refill(-1, 3)
		if delta >= 0: run.state.spawning.extend_refill(1, 3)
		run.prepare_spawn_plan()
		var count: int = run.state.next_refill_count()
		var preview: Array[SpawnToken] = run.state.spawning.preview(count)
		var batches: Dictionary[int, int] = run.state.spawning.refill_batches.duplicate()
		assert_true(FIXTURE.choose(run).accepted)
		var step: RunStepResult = run.advance()
		assert_eq(step.spawns.size(), count)
		for index: int in range(count): assert_eq(step.spawns[index].piece.match_color, preview[index].color)
		assert_eq(run.state.spawning.refill_batches, batches)
		run.advance()
		var mover: PieceState = run.state.rules.state.get_snapshot()[0]
		for target: Vector2i in run.state.rules.state.get_empty_coordinates():
			if not run.state.rules.validate_move(mover.piece_id, target).is_valid(): continue
			var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
			command.piece_id = mover.piece_id
			command.target = target
			assert_true(run.execute_command(command).accepted)
			break
		run.advance()
		assert_eq(run.advance().kind, &"spawn")
		for key: int in batches: assert_eq(run.state.spawning.refill_batches[key], maxi(0, batches[key] - 1))

func test_original_refill_obligation_finishes_before_any_recovery_check() -> void:
	var run: RunController = FIXTURE.run(true)
	run.state.pending_rewards = 0
	run.state.phase = RunState.Phase.INPUT
	run.state.rules.remove_piece(run.state.rules.state.get_piece_id(Vector2i(2, 2)))
	var mover: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 0)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = mover.piece_id
	command.target = Vector2i(2, 2)
	assert_false(run.execute_command(command).turn.direct_match)
	run.state.pending_rewards = 1
	run.enter_rewards()
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.advance().kind, &"end_turn")
	var step: RunStepResult = run.advance()
	assert_eq(step.kind, &"spawn")
	assert_eq(step.spawns.size(), 3)
	for spawn: SpawnResult in step.spawns: assert_eq(spawn.source, &"normal")
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 0)
	assert_eq(run.state.valid_moves, 1)

func test_all_pending_rewards_finish_before_recovery_and_share_one_budget() -> void:
	var run: RunController = FIXTURE.run(true)
	run.state.pending_rewards = 2
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.advance().kind, &"offer")
	assert_eq(run.state.spawn_history.size(), 0)
	assert_true(FIXTURE.choose(run, &"fixture_unlock_t").accepted)
	assert_eq(run.advance().kind, &"recovery")
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)
	assert_eq(run.state.rewards.consumed_count, 2)
	assert_eq(run.advance().kind, &"input")
	assert_eq(run.state.spawn_history.size(), 3)

func test_reward_wait_after_recovery_cannot_reset_budget_before_input_boundary() -> void:
	var run: RunController = FIXTURE.run(true)
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.advance().kind, &"recovery")
	# Explicit R08 fixture: a reward/leaf clears the recovered board before returning input.
	run.state.pending_rewards = 1
	run.enter_rewards()
	assert_true(FIXTURE.choose(run, &"fixture_unlock_t").accepted)
	run.abilities.resolve_removal(run.state.rules.state.get_snapshot(), &"fixture_clear")
	run.advance()
	assert_eq(run.state.rule_error, "empty_board_after_recovery")
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)
	assert_eq(run.state.spawn_history.size(), 3)

func test_real_continuous_milestone_rewards_keep_one_recovery_budget() -> void:
	var run: ChainRecovery = ChainRecovery.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, ShapeUnlockDemo.PROFILE)
	run.initialize("fixture_shape_unlock_empty")
	run.extra_recovery_score = 200 # Explicit fixture score; actual progression crosses 100 and 250.
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.advance().kind, &"recovery")
	assert_eq(run.state.pending_rewards, 2)
	assert_eq(run.state.progression.level, 2)
	var random_before: int = run.state.random.state
	assert_eq(run.advance().kind, &"offer")
	assert_true(FIXTURE.choose(run, &"fixture_unlock_t").accepted)
	assert_eq(run.state.pending_rewards, 1)
	assert_true(run.state.rules.shape_unlocks.recovery_attempted)
	assert_eq(run.advance().kind, &"offer")
	assert_true(FIXTURE.choose(run, &"refill_less").accepted)
	assert_eq(run.state.pending_rewards, 0)
	assert_eq(run.state.random.state, random_before)
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)
	# A final fixture removal models a later reward leaf emptying the board.
	run.abilities.resolve_removal(run.state.rules.state.get_snapshot(), &"fixture_clear")
	run.advance()
	assert_eq(run.state.rule_error, "empty_board_after_recovery")
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 1)

func test_still_empty_after_one_recovery_is_error_not_recursive_or_board_full() -> void:
	var run: ClearRecovery = ClearRecovery.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, ShapeUnlockDemo.PROFILE)
	run.initialize("fixture_shape_unlock_empty")
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.advance().kind, &"recovery")
	assert_eq(run.state.rule_error, "empty_board_after_recovery")
	assert_eq(run.state.phase, RunState.Phase.ERROR)
	assert_false(run.state.is_game_over)
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.advance().kind, &"error")
	assert_eq(run.state.spawn_history.size(), 3)

func test_ended_error_or_retired_run_cannot_start_recovery() -> void:
	for reason: StringName in [&"ended", &"error", &"retired"]:
		var run: RunController = FIXTURE.run(true)
		assert_true(FIXTURE.choose(run).accepted)
		if reason == &"ended": run.finish_game(&"challenge_completed")
		elif reason == &"error": run.report_error("fixture_failure")
		else: run.retire()
		run.advance()
		assert_eq(run.state.spawn_history.size(), 0)

func test_recovery_first_birth_chain_settles_rewards_then_finishes_remaining_tokens() -> void:
	var run: ChainRecovery = ChainRecovery.new(BoardRules.new(BoardState.new(9, 9), 5), 118, null, ShapeUnlockDemo.PROFILE)
	run.initialize("fixture_shape_unlock_empty")
	run.state.explosion.upgrades[&"chain_reward"] = 1
	assert_true(FIXTURE.choose(run).accepted)
	var old_root: int = run.state.rule_action_id
	var step: RunStepResult = run.advance()
	assert_eq(step.kind, &"recovery")
	assert_eq(step.spawns.size(), 3)
	assert_eq(step.spawns[0].matches[0].match_source, &"recovery_birth")
	assert_eq(step.spawns[0].matches.size(), 3, "L then F→Q and Q→R")
	assert_eq(step.matches.size(), 1)
	assert_eq(step.matches[0].score_entry.reason, &"chain_reward")
	assert_eq(step.matches[0].score_entry.final_score, DemolitionRules.CONFIG.chain_reward)
	assert_ne(run.state.rule_action_id, old_root)
	assert_eq(run.state.rules.state.get_piece_count(), 2)
	assert_true(run.state.explosion.actions.is_empty(), "completed recovery root must be retired")
	assert_eq(run.state.valid_moves, 0)
	assert_eq(run.state.stage.used_actions, 0)

func test_unlock_and_recovery_score_do_not_settle_stage_or_increment_pressure() -> void:
	var config: StageConfig = StageConfig.new()
	config.targets = [250, 500]
	config.pressure_intervals = [3, 3]
	var run: RunController = FIXTURE.run(true, config)
	run.state.ledger.commit(0, 1.0, 230, &"fixture", 0, [])
	assert_true(FIXTURE.choose(run).accepted)
	assert_eq(run.state.ledger.total, 280)
	assert_eq(run.state.stage.used_actions, 0)
	assert_true(run.state.stage.history.is_empty())
	assert_eq(run.advance().kind, &"recovery")
	assert_eq(run.state.stage.used_actions, 0)
	assert_true(run.state.stage.history.is_empty())
	assert_eq(run.advance().kind, &"input")
	var piece: PieceState = run.state.rules.state.get_snapshot()[0]
	for target: Vector2i in run.state.rules.state.get_empty_coordinates():
		if not run.state.rules.validate_move(piece.piece_id, target).is_valid(): continue
		var move: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
		move.piece_id = piece.piece_id
		move.target = target
		assert_true(run.execute_command(move).accepted)
		break
	run.advance()
	var settled: RunStepResult = run.advance()
	assert_not_null(settled.challenge)
	assert_eq(settled.challenge.reason, &"stage_passed")
	assert_eq(run.state.stage.history.size(), 1)
	assert_true(run.state.rules.shape_unlocks.contains(&"l"))
	assert_true(FIXTURE.choose(run, &"fixture_unlock_t").accepted)
	run.advance()
	assert_eq(run.state.stage.used_actions, 0)
	assert_true(run.state.rules.shape_unlocks.contains(&"l"))
