extends GutTest

const F: Script = preload("res://tests/support/screening_fixture.gd")

func test_six_versioned_configs_use_one_read_only_template_and_shared_budget() -> void:
	assert_eq(ScreeningDeck.CONFIGS.size(), 6)
	assert_eq(ScreeningDeck.modes().size(), 24)
	for key: String in ScreeningDeck.CONFIGS:
		var settings: ScreeningConfig = ScreeningDeck.config(key)
		assert_eq(settings.config_id, StringName("screening-%s-v1" % key))
		assert_eq(settings.action_limit, 15)
		assert_eq(settings.time_limit_seconds, 480)
		assert_eq(settings.seed_value, 119)
		var run: RunController = ScreeningDeck.new_run(key, "free")
		assert_eq(run.state.rules.match_templates().size(), 0 if key == "baseline" else 1)
		assert_true(run.state.rules.shape_unlocks.ids().is_empty())
		var templates: Array[MatchShapeTemplate] = run.state.rules.match_templates()
		if not templates.is_empty(): templates[0].offsets.clear()
		assert_eq(ScreeningDeck.footprint(key).size(), 5)

func test_free_openings_streams_and_production_catalog_match_baseline() -> void:
	var baseline: RunController = ScreeningDeck.new_run("baseline", "free")
	var original: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 119)
	var production: String = RunSnapshot.canonical(RunSnapshot.config(original).skills)
	for key: String in ScreeningDeck.CONFIGS:
		var run: RunController = ScreeningDeck.new_run(key, "free")
		assert_eq(run.initialization, "normal")
		assert_eq(run.prototype_profile, RunController.SCREENING_PROFILE)
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run).pieces), RunSnapshot.canonical(RunSnapshot.capture(baseline).pieces))
		assert_eq(run.state.random.state, baseline.state.random.state)
		assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), RunSnapshot.canonical(baseline.state.spawning.plan_data()))
		assert_eq(RunSnapshot.canonical(RunSnapshot.config(run).skills), production)
		assert_false(run.offer_catalog().any(func(skill: SkillDefinition) -> bool: return String(skill.skill_id).begins_with("fixture_")))
		assert_eq(run.state.ledger.total, 0)
		run.recorder = RunRecorder.new()
		run.recorder.begin(run, "screening_automated_fixture", true, "development", "user://screening_free_records")
		run.recorder.finish(run, "censored", "screening_opening_probe")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(run.recorder.path), replay.error)

func test_all_twenty_four_literal_task_answers_real_commands_and_disk_replay() -> void:
	var union_sizes: Array[int] = [5, 7, 9, 9, 8, 8]
	for index: int in range(ScreeningDeck.CONFIGS.size()):
		for task: String in ScreeningDeck.TASKS.slice(1):
			var run: RunController = ScreeningDeck.new_run(ScreeningDeck.CONFIGS[index], task)
			run.recorder = RunRecorder.new()
			run.recorder.begin(run, "screening_automated_fixture", true, "development", "user://screening_task_records")
			var initial: Dictionary = RunSnapshot.capture(run)
			var response: CommandResult = F.move(run)
			assert_true(response.accepted, response.reason)
			var n: int = union_sizes[index] if task == "overlap" else 5
			assert_eq(response.turn.direct_match, task != "wrong")
			assert_eq(run.state.ledger.total, 0 if task == "wrong" else n * (n + 5))
			if task != "wrong":
				assert_eq(response.turn.matches.size(), 1)
				assert_eq(response.turn.matches[0].removed.size(), n)
				assert_eq(response.turn.matches[0].match_source, &"direct_move")
			assert_not_null(F.settle(run))
			assert_eq(run.state.valid_moves, 1)
			assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 0)
			if task == "outside":
				assert_eq(run.state.rules.state.get_piece_count(), 2)
				assert_not_null(run.state.rules.state.get_piece_at(Vector2i(8, 0)))
			if task == "wrong": assert_eq(run.state.spawn_history.size(), 3)
			else: assert_eq(run.state.spawn_history.size(), 0)
			var prefix: RuleReplay = RuleReplay.new()
			assert_true(prefix.restore_prefix(run.recorder.records), prefix.error)
			run.recorder.finish(run, "censored", "screening_fixed_complete")
			var replay: RuleReplay = RuleReplay.new()
			assert_true(replay.replay_file(run.recorder.path), replay.error)
			assert_eq(replay.checked_records, run.recorder.records.size())
			assert_ne(RunSnapshot.canonical(initial.pieces), RunSnapshot.canonical(RunSnapshot.capture(run).pieces))

func test_wrong_color_never_creates_a_shape_before_spawn_and_outside_is_not_extended() -> void:
	for key: String in ScreeningDeck.CONFIGS:
		for task: String in ["wrong", "outside"]:
			var run: RunController = ScreeningDeck.new_run(key, task)
			var preview: BoardRules = run.state.rules.placement_preview()
			assert_true(preview.move_piece(preview.state.get_piece_id(ScreeningDeck.source(run.initialization)), ScreeningDeck.target(run.initialization)).is_valid())
			var groups: Array[BoardMatchGroup] = preview.find_matches_at(ScreeningDeck.target(run.initialization))
			assert_eq(groups.size(), 0 if task == "wrong" else 1)
			if task == "outside": assert_eq(groups[0].piece_ids.size(), 5)

func test_window_counts_activations_waits_for_safe_boundary_and_preserves_errors() -> void:
	var run: RunController = ScreeningDeck.new_run("l", "free")
	var settings: ScreeningConfig = ScreeningDeck.config("l")
	assert_eq(ScreeningWindow.reason(run, settings, false, 479999, true), "")
	assert_eq(ScreeningWindow.reason(run, settings, false, 480000, false), "")
	assert_eq(ScreeningWindow.reason(run, settings, false, 480000, true), "time_limit")
	run.state.valid_moves = 14
	run.state.activations = 1
	assert_eq(ScreeningWindow.reason(run, settings, false, 0, true), "action_limit")
	assert_eq(ScreeningWindow.reason(run, settings, false, 0, false), "")
	assert_eq(ScreeningWindow.reason(run, settings, true, 0, true), "fixed_complete")
	run.state.rule_error = "injected"
	assert_eq(ScreeningWindow.reason(run, settings, false, 0, false), "rule_error")
	run.state.rule_error = ""
	run.state.is_game_over = true
	assert_eq(ScreeningWindow.reason(run, settings, false, 0, false), "natural_end")

func test_profile_isolation_keeps_fixed_candidate_out_of_production_and_free_pool() -> void:
	var fixed: RunController = ScreeningDeck.new_run("l", "direct")
	assert_eq(fixed.offer_catalog()[0].skill_id, &"fixture_screening_refill")
	assert_eq(fixed.offer_catalog()[0].minimum_reward, 1)
	var original: SkillDefinition = load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition
	assert_eq(original.minimum_reward, 3)
	var free: RunController = ScreeningDeck.new_run("l", "free")
	free.initialize("screening_l_direct")
	assert_eq(free.state.rule_error, "unsupported_initialization")

func test_six_free_configs_complete_real_fifteen_action_bot_windows_with_production_rewards() -> void:
	for key: String in ScreeningDeck.CONFIGS:
		var run: RunController = ScreeningDeck.new_run(key, "free")
		var bot: RandomLegalBot = RandomLegalBot.new(119)
		run.recorder = RunRecorder.new()
		run.recorder.metadata = {"automation": "random-legal-v1", "participant": null, "config_id": ScreeningDeck.config(key).config_id}
		run.recorder.begin(run, "bot_screening_smoke", true, "development", "user://screening_bot_windows")
		var reason: String = ""
		for step_index: int in range(300):
			var ready: bool = run.state.phase == RunState.Phase.INPUT
			reason = ScreeningWindow.reason(run, ScreeningDeck.config(key), false, 0, ready)
			if not reason.is_empty(): break
			if run.state.phase not in [RunState.Phase.INPUT, RunState.Phase.REWARDS] or (run.state.phase == RunState.Phase.REWARDS and run.state.rewards.active_offer == null):
				run.advance()
				continue
			var command: RunCommand = bot.choose(run)
			assert_not_null(command)
			if command == null: break
			var result: CommandResult = run.execute_command(command)
			assert_true(result.accepted, result.reason)
			if not result.accepted: break
			if command is ChooseSkillCommand: run.advance()
		assert_eq(reason, "action_limit")
		assert_eq(run.state.valid_moves + run.state.activations, 15)
		assert_eq(run.state.rule_error, "")
		run.recorder.finish(run, "censored", "screening_action_limit")
		var replay: RuleReplay = RuleReplay.new()
		assert_true(replay.replay_file(run.recorder.path), replay.error)
