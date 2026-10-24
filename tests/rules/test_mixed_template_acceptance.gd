extends GutTest

const F: Script = preload("res://tests/support/mixed_template_fixture.gd")
const DEMO: Script = preload("res://gameplay/skills/debug/mixed_template_demo.gd")
const BIRTH: Script = preload("res://tests/support/square_template_fixture.gd")

func _complete(mode: String) -> RunController:
	var run: RunController = DEMO.new_run(mode)
	run.state.rules.remove_piece(run.state.rules.state.get_piece_id(DEMO.source(mode)))
	run.state.rules.place_piece(DEMO.target(mode), 0)
	return run

func test_literal_mixed_unions_independent_events_and_quantity_rewards() -> void:
	var sizes: Array[int] = [7, 9, 5, 11]
	var totals: Array[int] = [104, 146, 110, 196]
	for index: int in range(4):
		var run: RunController = _complete("fixture_mixed_" + DEMO.CASES[index])
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 2 if index == 2 else 1)
		assert_eq(groups[0].piece_ids.size(), sizes[index])
		if index == 2: assert_eq(groups[1].piece_ids.size(), 5)
		run.state.explosion.upgrades[&"precision_reward"] = 1
		run.state.explosion.upgrades[&"longline_reward"] = 1
		assert_eq(run.abilities.resolve(groups).size(), groups.size())
		assert_eq(run.state.ledger.total, totals[index])
		assert_eq(run.state.rules.state.get_piece_count(), 1)

func test_full_catalog_preserves_all_eight_shape_identities_and_line_geometry() -> void:
	var run: RunController = _complete("fixture_mixed_nested")
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	var ids: Array[StringName] = []
	for hit: BoardMatchHit in groups[0].hits:
		if not ids.has(hit.shape_id): ids.append(hit.shape_id)
		if hit.shape_id == &"line":
			assert_eq(hit.piece_ids.size(), 5)
			assert_eq(hit.direction, Vector2i.RIGHT)
	for shape: String in DEMO.SHAPES: assert_true(ids.has(StringName(shape)), shape)
	assert_true(ids.has(&"line"))
	assert_eq(groups[0].piece_ids.size(), 11)

func test_template_order_and_queries_do_not_change_geometry_state_or_resources() -> void:
	for id: String in DEMO.CASES:
		var run: RunController = _complete("fixture_mixed_" + id)
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var templates: Array[MatchShapeTemplate] = run.state.rules.match_templates()
		templates.reverse()
		var expected: Array[BoardMatchGroup] = run.state.rules.find_matches()
		var actual: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, templates)
		assert_eq(actual.size(), expected.size())
		for index: int in range(actual.size()): assert_eq(actual[index].piece_ids, expected[index].piece_ids)
		actual[0].hits[0].coordinates.clear()
		templates[0].offsets.clear()
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
		assert_eq(run.state.rules.find_matches()[0].piece_ids, expected[0].piece_ids)
		assert_eq(DEMO.templates(run.initialization)[0].offsets.size(), 5)

func test_baseline_has_identical_board_and_streams_but_independent_configuration() -> void:
	for id: String in DEMO.CASES:
		var mixed: RunController = DEMO.new_run("fixture_mixed_" + id)
		var baseline: RunController = DEMO.new_run("fixture_mixed_" + id + "_baseline")
		var mixed_before: Dictionary = RunSnapshot.capture(mixed)
		var baseline_before: Dictionary = RunSnapshot.capture(baseline)
		assert_eq(RunSnapshot.canonical(mixed_before.pieces), RunSnapshot.canonical(baseline_before.pieces))
		assert_eq(mixed.state.random.state, baseline.state.random.state)
		assert_eq(RunSnapshot.canonical(mixed.state.spawning.plan_data()), RunSnapshot.canonical(baseline.state.spawning.plan_data()))
		assert_ne(RunSnapshot.digest(RunSnapshot.config(mixed)), RunSnapshot.digest(RunSnapshot.config(baseline)))
		assert_true(mixed.state.rules.shape_unlocks.ids().is_empty(), "construction config is not a successful acquisition")
		assert_true(baseline.state.rules.match_templates().is_empty())

func test_all_eight_real_move_records_reward_continuation_and_disk_replay() -> void:
	var scores: Array[int] = [84, 126, 50, 176]
	for index: int in range(4):
		for baseline: bool in [false, true]:
			var mode: String = "fixture_mixed_" + DEMO.CASES[index] + ("_baseline" if baseline else "")
			var run: RunController = DEMO.new_run(mode)
			run.recorder = RunRecorder.new()
			run.recorder.begin(run, "mixed_technical_fixture", true, "development", "user://mixed_acceptance_records")
			var plan: String = RunSnapshot.canonical(run.state.spawning.plan_data())
			var response: CommandResult = F.move(run)
			assert_true(response.accepted, response.reason)
			var expected_score: int = (50 if index == 3 else 0) if baseline else scores[index]
			assert_eq(run.state.ledger.total, expected_score)
			assert_eq(response.turn.direct_match, not baseline or index == 3)
			if response.turn.direct_match:
				assert_eq(response.turn.matches.size(), 1)
				assert_eq(response.turn.matches[0].match_source, &"direct_move")
				assert_eq(response.turn.matches[0].removed.size(), (5 if baseline else [7, 9, 5, 11][index]))
			var prefix: RuleReplay = RuleReplay.new()
			assert_false(prefix.restore_prefix(run.recorder.records))
			assert_eq(prefix.error, "unsafe_prefix_phase")
			var step: RunStepResult = F.finish(run)
			assert_not_null(step)
			assert_eq(step.kind, &"input")
			assert_true(prefix.restore_prefix(run.recorder.records), prefix.error)
			assert_eq(RunSnapshot.canonical(RunSnapshot.capture(prefix.run)), RunSnapshot.canonical(RunSnapshot.capture(run)))
			assert_eq(run.state.valid_moves, 1)
			assert_eq(run.state.rewards.consumed_count, 1 if expected_score >= 100 else 0)
			assert_eq(run.state.rules.shape_unlocks.recovery_batch_id, 0)
			if response.turn.direct_match:
				assert_true(run.state.spawn_history.is_empty())
				assert_eq(RunSnapshot.canonical(run.state.spawning.plan_data()), plan)
			else: assert_eq(run.state.spawn_history.size(), 3)
			if index == 2 and not baseline:
				assert_eq(run.state.rules.state.get_piece_count(), 6, "unrelated pre-existing X is outside landing group")
			run.recorder.finish(run, "censored", "mixed_acceptance")
			var replay: RuleReplay = RuleReplay.new()
			assert_true(replay.replay_file(run.recorder.path), replay.error)
			assert_eq(replay.checked_records, run.recorder.records.size())

func test_preview_uses_same_mixed_landing_union_without_touching_live_state() -> void:
	for mode: String in DEMO.MODES:
		var run: RunController = DEMO.new_run(mode)
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		var preview: BoardRules = run.state.rules.placement_preview()
		assert_true(preview.move_piece(preview.state.get_piece_id(DEMO.source(mode)), DEMO.target(mode)).is_valid())
		var groups: Array[BoardMatchGroup] = preview.find_matches_at(DEMO.target(mode))
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
		var moved: CommandResult = F.move(run)
		assert_eq(moved.turn.matches.size(), groups.size())
		for index: int in range(groups.size()): assert_eq(moved.turn.matches[index].removed.size(), groups[index].piece_ids.size())

func test_batch_dye_scans_all_groups_including_unrelated_independent_x() -> void:
	var scores: Array[int] = [84, 126, 100, 176]
	for index: int in range(4):
		var run: RunController = _complete("fixture_mixed_" + DEMO.CASES[index])
		var ids: Array[int] = []
		for piece: PieceState in run.state.rules.state.get_snapshot():
			if piece.match_color == 0:
				run.state.rules.set_piece_color(piece.piece_id, 2)
				ids.append(piece.piece_id)
		var results: Array[MatchResult] = DyeRules.recolor(run.abilities, ids, 0)
		assert_eq(results.size(), 3 if index == 2 else 2)
		assert_eq(run.state.ledger.total, scores[index])
		assert_eq(run.state.rules.state.get_piece_count(), 1)
		for result: MatchResult in results.slice(1): assert_eq(result.match_source, &"dye")
		assert_false(run.direct_match())

func test_birth_resolves_landing_union_and_continues_remaining_tokens() -> void:
	var counts: Array[int] = [7, 9, 5, 11]
	for index: int in range(4):
		var mode: String = "fixture_mixed_" + DEMO.CASES[index]
		var run: RunController = DEMO.new_run(mode)
		run.state.rules.remove_piece(run.state.rules.state.get_piece_id(DEMO.source(mode)))
		var tokens: Array[SpawnToken] = run.state.spawning.preview(3)
		for piece: PieceState in run.state.rules.state.get_snapshot():
			if piece.coordinate != Vector2i(8, 8): run.state.rules.set_piece_color(piece.piece_id, tokens[0].color)
		assert_true(BIRTH.next_coordinate(run, DEMO.target(mode)))
		var results: Array[SpawnResult] = run.spawn_batch(3)
		assert_eq(results.size(), 3)
		assert_eq(results[0].matches.size(), 1)
		assert_eq(results[0].matches[0].removed.size(), counts[index])
		assert_eq(results[0].matches[0].match_source, &"birth")
		for token: int in range(3): assert_eq(results[token].piece.match_color, tokens[token].color)
		assert_false(run.direct_match())

func test_fixture_catalog_does_not_change_production_minimum_or_older_profiles() -> void:
	var original: SkillDefinition = load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition
	assert_eq(original.minimum_reward, 3)
	var run: RunController = DEMO.new_run("fixture_mixed_lt")
	assert_eq(run.offer_catalog()[0].minimum_reward, 1)
	assert_eq(run.offer_catalog()[0].skill_id, &"fixture_mixed_refill")
	assert_eq(original.minimum_reward, 3)
	var production: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 119)
	assert_false(production.offer_catalog().any(func(s: SkillDefinition) -> bool: return s.skill_id == &"fixture_mixed_refill"))
	production.initialize("fixture_mixed_lt")
	assert_eq(production.state.rule_error, "unsupported_initialization")
	assert_eq(production.state.rules.state.get_piece_count(), 0)

func test_nearby_plus_and_x_can_create_a_real_bridge_and_must_not_be_counted_independently() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5, DEMO.templates("fixture_mixed_independent")), 119)
	var cells: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(3, 0), Vector2i(5, 0), Vector2i(4, 1), Vector2i(3, 2), Vector2i(5, 2)]
	for cell: Vector2i in cells: run.state.rules.place_piece(cell, 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 10)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"plus"))
	assert_true(groups[0].hits.filter(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"x").size() > 1)
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 10)
	assert_eq(run.state.ledger.total, 150)
