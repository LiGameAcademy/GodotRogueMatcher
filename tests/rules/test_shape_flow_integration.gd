extends GutTest

const L: MatchShapeTemplate = preload("res://gameplay/board/matching/l_template.tres")

func _run(enabled: bool = true) -> RunController:
	var templates: Array[MatchShapeTemplate] = []
	if enabled: templates.append(L)
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), 118)

func _l(run: RunController, missing: Vector2i = Vector2i(-1, -1), color: int = 0) -> void:
	for coordinate: Vector2i in L.offsets:
		if coordinate != missing: run.state.rules.place_piece(coordinate, color)

func _move(run: RunController, piece: PieceState, target: Vector2i) -> CommandResult:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = piece.piece_id
	command.target = target
	return run.execute_command(command)

func _next_coordinate(run: RunController, target: Vector2i) -> void:
	var empty: Array[Vector2i] = run.state.rules.state.get_empty_coordinates()
	for seed_value: int in range(10000):
		var sample: RandomNumberGenerator = RandomNumberGenerator.new()
		sample.seed = seed_value
		if empty[sample.randi_range(0, empty.size() - 1)] == target:
			run.state.random.seed = seed_value
			return
	fail_test("fixture requires a deterministic landing seed")

func test_direct_l_move_skips_refill_without_consuming_plan_or_finite_batches() -> void:
	var run: RunController = _run()
	_l(run, Vector2i(2, 2))
	var mover: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 0)
	run.state.rules.place_piece(Vector2i(8, 8), 1)
	run.state.spawning.extend_refill(-1, 3)
	run.start_turn()
	var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
	var response: CommandResult = _move(run, mover, Vector2i(2, 2))
	assert_true(response.accepted)
	assert_true(response.turn.direct_match)
	assert_eq(response.turn.matches[0].removed.size(), 5)
	assert_eq(response.turn.matches[0].hits[0].shape_id, &"l")
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.valid_moves, 1)
	assert_eq(run.advance().kind, &"end_turn")
	assert_true(run.advance().spawns.is_empty())
	assert_eq(run.state.spawning.refill_batches[-1], 3)
	assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)

func test_direct_l_full_clear_still_consumes_one_actual_refill_batch() -> void:
	var run: RunController = _run()
	_l(run, Vector2i(2, 2))
	var mover: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 0)
	run.state.spawning.extend_refill(-1, 3)
	run.start_turn()
	var preview: Array[SpawnToken] = run.state.spawning.preview(2)
	assert_true(_move(run, mover, Vector2i(2, 2)).turn.direct_match)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	run.advance()
	var step: RunStepResult = run.advance()
	assert_eq(step.spawns.size(), 2)
	assert_eq(run.state.spawning.refill_batches[-1], 2)
	for index: int in range(2): assert_eq(step.spawns[index].piece.match_color, preview[index].color)

func test_disabled_l_and_unrelated_l_do_not_grant_move_refill_exemption() -> void:
	for enabled: bool in [false, true]:
		var run: RunController = _run(enabled)
		_l(run)
		var mover: PieceState = run.state.rules.place_piece(Vector2i(7, 7), 1)
		run.start_turn()
		var response: CommandResult = _move(run, mover, Vector2i(7, 6))
		assert_true(response.accepted)
		assert_false(response.turn.direct_match)
		assert_eq(run.state.ledger.total, 0)
		run.advance()
		assert_eq(run.advance().spawns.size(), 3)

func test_birth_matches_l_then_finishes_locked_batch_in_order() -> void:
	var run: RunController = _run()
	run.prepare_spawn_plan()
	var preview: Array[SpawnToken] = run.state.spawning.preview(3)
	_l(run, Vector2i(2, 2), preview[0].color)
	run.state.rules.place_piece(Vector2i(8, 8), (preview[0].color + 1) % 5)
	_next_coordinate(run, Vector2i(2, 2))
	var births: Array[SpawnResult] = run.spawn_batch(3)
	assert_eq(births.size(), 3)
	assert_eq(births[0].piece.coordinate, Vector2i(2, 2))
	assert_eq(births[0].matches[0].removed.size(), 5)
	assert_eq(births[0].matches[0].hits[0].shape_id, &"l")
	assert_eq(run.state.ledger.total, 50)
	assert_eq(run.state.rules.state.get_piece_count(), 3)
	assert_eq(run.state.spawn_history.size(), 3)
	for index: int in range(3): assert_eq(births[index].piece.match_color, preview[index].color)
	assert_eq(run.state.spawning.preview(3).size(), 0)
	assert_false(run.direct_match())

func test_batch_recolor_finishes_all_targets_before_one_union_match() -> void:
	var run: RunController = _run()
	_l(run, Vector2i(2, 2))
	var ids: Array[int] = []
	for x: int in range(2, 5): ids.append(run.state.rules.place_piece(Vector2i(x, 2), 1).piece_id)
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	var results: Array[MatchResult] = DyeRules.recolor(run.abilities, ids, 0)
	assert_eq(results.size(), 2)
	assert_eq(results[0].cause, &"dye")
	assert_eq(results[0].recolored.size(), 3)
	assert_eq(results[1].removed.size(), 7)
	assert_eq(run.state.ledger.total, 104)
	assert_gte(results[1].hits.size(), 2)
	assert_false(run.direct_match())
	var events: Array[Dictionary] = RunRecorder.matches(results)
	assert_true(events[1].has("match_hits"))
	assert_eq(events[1].cause, "match")
	assert_eq(events[1].score.action_id, "0")

func test_skill_l_after_nonmatching_move_does_not_retroactively_skip_refill() -> void:
	var run: RunController = _run()
	_l(run, Vector2i(2, 2))
	var dyed: PieceState = run.state.rules.place_piece(Vector2i(2, 2), 1)
	var mover: PieceState = run.state.rules.place_piece(Vector2i(7, 7), 2)
	run.start_turn()
	assert_false(_move(run, mover, Vector2i(7, 6)).turn.direct_match)
	assert_eq(DyeRules.recolor(run.abilities, [dyed.piece_id], 0)[1].removed.size(), 5)
	assert_false(run.direct_match())
	run.advance()
	assert_eq(run.advance().spawns.size(), 3)

func test_query_preview_and_other_runs_cannot_mutate_enabled_configuration() -> void:
	var source: MatchShapeTemplate = L.duplicate(true) as MatchShapeTemplate
	var rules: BoardRules = BoardRules.new(BoardState.new(9, 9), 5, [source])
	var other: RunController = _run(false)
	source.offsets.clear()
	rules.match_templates()[0].offsets.clear()
	var preview: BoardRules = rules.placement_preview()
	for coordinate: Vector2i in L.offsets:
		rules.place_piece(coordinate, 0)
		other.state.rules.place_piece(coordinate, 0)
	assert_eq(rules.find_matches().size(), 1)
	assert_true(other.state.rules.find_matches().is_empty())
	assert_true(preview.state.get_snapshot().is_empty())
	assert_eq(preview.match_templates()[0].offsets, L.offsets)
	assert_eq(L.offsets.size(), 5)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(RunController.new(rules, 1))), RunSnapshot.digest(RunSnapshot.config(_run())))

func test_preflight_special_placement_sees_enabled_l_before_mutation() -> void:
	for line: bool in [false, true]:
		var run: RunController = _run()
		_l(run, Vector2i(2, 2))
		var config: ExplosionConfig = run.abilities.config.duplicate(true) as ExplosionConfig
		config.event_budget = 1
		run.abilities = AbilityResolver.new(run.state, config)
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		request.coordinate = Vector2i(2, 2)
		request.color = 0
		request.stat = LineClearState.AXIS_ROW
		request.kind = ChoiceEffectRequest.Kind.UNLOCK_LINE if line else ChoiceEffectRequest.Kind.UNLOCK_CORE
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var reason: String = AbilityEffectRunner._preflight_unlock_line(run, request) if line else AbilityEffectRunner._preflight_unlock_core(run, request)
		assert_false(reason.is_empty())
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_prototype_config_and_real_l_commands_replay_every_checkpoint() -> void:
	var run: RunController = _run()
	run.initialize("fixture_dye")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "shape_prototype_test", false)
	var origins: Array[Vector2i] = [Vector2i(3, 4), Vector2i(2, 4), Vector2i(4, 6)]
	var targets: Array[Vector2i] = [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]
	for index: int in range(origins.size()):
		var mover: PieceState = run.state.rules.state.get_piece_at(origins[index])
		assert_not_null(mover)
		if mover == null: return
		var response: CommandResult = _move(run, mover, targets[index])
		assert_true(response.accepted, response.reason)
		if not response.accepted: return
		while run.continuation != &"idle" and run.state.pending_rewards == 0:
			run.advance()
	var found: bool = false
	for record: Dictionary in run.recorder.records:
		for event: Dictionary in record.get("events", []):
			found = found or event.has("match_hits")
	assert_true(found, "fixture must actually trigger a template, not just carry its configuration")
	run.recorder.finish(run, "censored", "prototype_slice")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)
	assert_eq(replay.checked_records, run.recorder.records.size())
	assert_eq(replay.run.state.rules.match_templates()[0].offsets, L.offsets)
	var changed: Array[Dictionary] = run.recorder.records.duplicate(true)
	changed[0].config.prototype_match_templates[0].offsets[0] = ["99", "0"]
	assert_false(replay.replay(changed))
	assert_eq(replay.error, "invalid_match_templates")
	changed = run.recorder.records.duplicate(true)
	for record: Dictionary in changed:
		for event: Dictionary in record.get("events", []):
			if event.has("match_hits"): event.match_hits[0].shape_id = "tampered"
	assert_false(replay.replay(changed))
	assert_true(replay.error.contains("seq="))

func test_real_reward_choice_batches_dye_before_union_and_consumes_once() -> void:
	var run: RunController = _run()
	_l(run, Vector2i(2, 2))
	for x: int in range(2, 5): run.state.rules.place_piece(Vector2i(x, 2), 1)
	run.state.rewards.acquired[&"match_dye_echo"] = 1
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	run.state.rewards.consumed_count = 2
	run.state.pending_rewards = 1
	run.enter_rewards()
	for seed_value: int in range(20):
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		if random.randi_range(0, 1) == 0:
			run.state.rewards.target_random.seed = seed_value
			break
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([preload("res://gameplay/progression/content/instant_color_dye.tres")])
	var offer: SkillOffer = run.prepare_offer(false, generator)
	assert_not_null(offer)
	if offer == null: return
	assert_eq(offer.targets[offer.choices[0].skill_id].color, 0)
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, 0)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = offer.choices[0].skill_id
	var response: CommandResult = run.execute_command(command)
	assert_true(response.accepted, response.reason)
	if not response.accepted: return
	assert_eq(response.skill.matches[0].recolored.size(), 3)
	assert_eq(response.skill.matches[1].removed.size(), 7)
	assert_eq(run.state.ledger.total, 84)
	assert_eq(run.state.rewards.consumed_count, 3)
	assert_same(run.execute_command(command), response)
	assert_eq(run.state.rewards.consumed_count, 3)
	assert_eq(run.state.valid_moves, 0)
	assert_false(run.direct_match())

func test_invalid_record_templates_are_rejected_without_loading_resources() -> void:
	for value: Variant in [null, {}, {"shape_id": "l", "offsets": [["0", "0"], ["0", "0"]]}, {"shape_id": "line", "offsets": [["0", "0"]]}, {"shape_id": "l", "offsets": [[0.0, "0"]]}, {"shape_id": "l", "offsets": [["-9223372036854775808", "0"]]}]:
		assert_null(MatchShapeTemplate.from_record(value))

func test_runtime_and_replay_share_configuration_limits() -> void:
	var shifted: MatchShapeTemplate = L.duplicate(true) as MatchShapeTemplate
	for index: int in range(shifted.offsets.size()): shifted.offsets[index] += Vector2i(100, 100)
	assert_false(BoardMatchDetector.validation_error([shifted]).is_empty())
	assert_null(MatchShapeTemplate.from_record(RunSnapshot.normalize({"shape_id": "l", "offsets": shifted.offsets})))
	var templates: Array[MatchShapeTemplate] = []
	for index: int in range(BoardMatchDetector.MAXIMUM_TEMPLATES + 1): templates.append(L)
	assert_false(BoardMatchDetector.validation_error(templates).is_empty())
	templates.pop_back()
	assert_eq(BoardMatchDetector.validation_error(templates), "")
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), 118)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "maximum_template_config_test", false)
	run.recorder.finish(run, "censored", "configuration_boundary")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(run.recorder.records), replay.error)
