extends GutTest

func _config(targets: Array[int] = [100000], intervals: Array[int] = [4]) -> StageConfig:
	var config: StageConfig = StageConfig.new()
	config.targets = targets
	config.pressure_intervals = intervals
	return config

func _run(config: StageConfig = null) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 17, _config() if config == null else config)
	run.state.rules.place_piece(Vector2i(0, 0), 0)
	run.start_turn()
	return run

func _move(run: RunController, source: Vector2i, target: Vector2i) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(source)
	command.target = target
	return run.execute_command(command)

func _finish_action(run: RunController) -> RunStepResult:
	run.advance()
	return run.advance()

func test_pressure_boundaries_are_completed_actions_and_have_no_death_line() -> void:
	var stage: StageState = StageState.new(_config())
	for actions: int in [0, 3, 4, 7, 8, 11, 12, 100]:
		stage.used_actions = actions
		assert_eq(stage.base_refill_count(), mini(6, 3 + int(actions / 4.0)))
		assert_true(stage.can_act())
	var config: StageConfig = _config([10, 20, 30], [4, 3, 2])
	stage = StageState.new(config)
	for index: int in range(3):
		stage.index = index
		stage.used_actions = config.pressure_intervals[index]
		assert_eq(stage.base_refill_count(), 4)

func test_action_at_pressure_boundary_pays_locked_cost_then_previews_increase() -> void:
	var run: RunController = _run()
	run.state.stage.used_actions = 3
	run.prepare_spawn_plan()
	var planned: Array[SpawnToken] = run.state.spawning.preview(3)
	assert_true(_move(run, Vector2i.ZERO, Vector2i(1, 0)).accepted)
	assert_eq(run.action_refill_count, 3)
	assert_eq(run.state.stage.used_actions, 4)
	var step: RunStepResult = _finish_action(run)
	assert_eq(step.spawns.size(), 3)
	for index: int in range(3): assert_eq(step.spawns[index].piece.match_color, planned[index].color)
	run.advance()
	assert_eq(run.state.next_refill_count(), 4)
	assert_eq(run.state.spawning.preview(4).size(), 4)

func test_goal_action_pays_six_before_relief_and_offer_uses_next_stage_base() -> void:
	var run: RunController = _run(_config([100, 200], [4, 4]))
	run.state.stage.used_actions = 12
	run.state.stage.carry_in = 100
	run.prepare_spawn_plan()
	assert_true(_move(run, Vector2i.ZERO, Vector2i(1, 0)).accepted)
	var step: RunStepResult = _finish_action(run)
	assert_eq(step.spawns.size(), 6)
	assert_eq(step.challenge.reason, &"stage_passed")
	assert_eq(step.challenge.base_refill_before_relief, 6)
	assert_eq(step.challenge.next_base_refill, 3)
	assert_eq(run.state.next_refill_count(), 3)
	assert_eq(SkillRules.effect_context(run.state).next_refill, 3)
	assert_eq(run.state.pending_rewards, 1)

func test_six_to_three_to_six_preserves_all_tokens_and_content_random() -> void:
	var run: RunController = _run(_config([1, 100000], [4, 2]))
	run.state.stage.used_actions = 12
	run.prepare_spawn_plan()
	var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	var random_before: int = run.state.spawning.content_random.state
	run.state.stage.begin_action(1, 0)
	run.state.stage.carry_in = 1
	assert_eq(run.state.stage.settle([], false, 1).reason, &"stage_passed")
	run.prepare_spawn_plan()
	assert_eq(run.state.next_refill_count(), 3)
	assert_eq(run.state.spawning.preview(3).size(), 3)
	run.state.stage.start_next()
	run.state.stage.used_actions = 6
	run.prepare_spawn_plan()
	assert_eq(run.state.next_refill_count(), 6)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)
	assert_eq(run.state.spawning.content_random.state, random_before)

func test_direct_match_preserves_modifiers_but_full_clear_pays_locked_refill() -> void:
	for full_clear: bool in [false, true]:
		var run: RunController = _run()
		run.state.rules.remove_piece(run.state.rules.state.get_piece_id(Vector2i.ZERO))
		for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 4), 0)
		run.state.rules.place_piece(Vector2i(4, 6), 0)
		if not full_clear: run.state.rules.place_piece(Vector2i(8, 8), 1)
		run.state.stage.used_actions = 4
		run.state.spawning.extend_refill(-1, 3)
		run.prepare_spawn_plan()
		var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
		assert_true(_move(run, Vector2i(4, 6), Vector2i(4, 4)).accepted)
		var step: RunStepResult = _finish_action(run)
		assert_eq(run.state.stage.used_actions, 5)
		assert_eq(step.spawns.size(), 3 if full_clear else 0)
		assert_eq(run.state.spawning.refill_batches[-1], 2 if full_clear else 3)
		if not full_clear: assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)

func test_temporary_counts_clamp_at_six_and_both_expire_on_real_refill() -> void:
	var run: RunController = _run()
	run.state.stage.used_actions = 12
	run.state.spawning.extend_refill(1, 1)
	assert_eq(run.state.next_refill_count(), 6)
	run.state.spawning.extend_refill(-1, 1)
	assert_eq(run.state.next_refill_count(), 6)
	assert_true(_move(run, Vector2i.ZERO, Vector2i(1, 0)).accepted)
	assert_eq(_finish_action(run).spawns.size(), 6)
	assert_eq(run.state.spawning.refill_batches[1], 0)
	assert_eq(run.state.spawning.refill_batches[-1], 0)

func test_config_roundtrip_rejects_old_budget_and_invalid_pressure() -> void:
	var config: StageConfig = _config([100, 200], [4, 3])
	var restored: StageConfig = StageConfig.from_record(RunSnapshot.resource_fields(config))
	assert_not_null(restored)
	assert_eq(restored.pressure_intervals, [4, 3])
	assert_eq(restored.base_refill, 3)
	assert_null(StageConfig.from_record({"targets": [100], "action_limits": [10]}))
	config.maximum_refill = 7
	assert_ne(config.validation_error(), "")

func test_reset_restores_pressure_without_mutating_other_run_or_config() -> void:
	var config: StageConfig = _config()
	var a: RunController = _run(config)
	var b: RunController = _run(config)
	a.state.stage.used_actions = 12
	assert_eq(a.state.next_refill_count(), 6)
	assert_eq(b.state.next_refill_count(), 3)
	a.state.reset_counters()
	assert_eq(a.state.next_refill_count(), 3)
	assert_eq(config.pressure_intervals, [4])
	assert_eq(config.base_refill, 3)

func test_birth_match_frees_space_and_remaining_six_piece_batch_finishes() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(5, 1), 5), 17, _config([50, 100], [4, 4]))
	var spawning: SpawnConfig = SpawnConfig.new()
	spawning.color_weights = [4, 0, 0, 0, 0]
	run.state.spawning = SpawnState.new(spawning, 17)
	run.state.rules.place_piece(Vector2i(0, 0), 0)
	run.state.rules.place_piece(Vector2i(2, 0), 0)
	run.state.stage.used_actions = 12
	run.start_turn()
	assert_true(_move(run, Vector2i.ZERO, Vector2i(1, 0)).accepted)
	var step: RunStepResult = _finish_action(run)
	assert_eq(step.spawns.size(), 6)
	assert_eq(run.state.rules.state.get_piece_count(), 3)
	assert_eq(run.state.stage.action_score, 50)
	assert_eq(step.challenge.reason, &"stage_passed")
	assert_false(run.state.is_game_over)
