extends GutTest

const F: Script = preload("res://tests/support/x_template_fixture.gd")

func test_x_matches_confirmed_resource_and_has_one_unique_orientation() -> void:
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2)]
	assert_eq(F.X.shape_id, &"x")
	assert_eq(F.X.offsets, expected)
	var variants: Array[MatchShapeTemplate] = F.X.variants()
	assert_eq(variants.size(), 1)
	var run: RunController = F.run()
	F.place(run, expected, Vector2i(2, 2))
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.X, F.X])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].hits.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(groups[0].hits[0].shape_id, &"x")

func test_each_missing_or_wrong_color_cell_and_all_clipped_edges_refuse_x() -> void:
	for cell: Vector2i in F.X.offsets:
		for wrong: bool in [false, true]:
			var run: RunController = F.run()
			F.place(run, F.X.offsets, Vector2i.ZERO, 0, cell)
			if wrong: run.state.rules.place_piece(cell, 1)
			assert_true(run.state.rules.find_matches().is_empty())
	for origin: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(7, 0), Vector2i(0, 7)]:
		var run: RunController = F.run()
		for cell: Vector2i in F.X.offsets:
			if run.state.rules.state.is_valid_coordinate(origin + cell): run.state.rules.place_piece(origin + cell, 0)
		assert_true(run.state.rules.find_matches().is_empty())

func test_edge_extra_color_neither_blocks_nor_extends_x() -> void:
	for color: int in [0, 1]:
		var run: RunController = F.run()
		F.place(run, F.X.offsets)
		var extra: PieceState = run.state.rules.place_piece(Vector2i(1, 0), color)
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 5)
		assert_false(groups[0].piece_ids.has(extra.piece_id))

func test_long_arm_merges_before_landing_filter_and_scores_union_once() -> void:
	var run: RunController = F.run()
	F.place(run, F.X.offsets)
	for axis: int in [3, 4]: run.state.rules.place_piece(Vector2i(axis, axis), 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches_at(Vector2i(4, 4))
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"x"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"line"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 7)
	assert_eq(run.state.ledger.total, 104)

func test_shared_l_x_union_and_separate_shapes_keep_distinct_groups() -> void:
	var run: RunController = F.run(true, true)
	F.place(run, F.L.offsets)
	F.place(run, F.X.offsets)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"l"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"x"))
	var separate: RunController = F.run(true, true)
	F.place(separate, F.L.offsets)
	F.place(separate, F.X.offsets, Vector2i(5, 5))
	groups = separate.state.rules.find_matches()
	assert_eq(groups.size(), 2)
	separate.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(separate.abilities.resolve(groups).size(), 2)
	assert_eq(separate.state.ledger.total, 110)

func test_three_x_hits_merge_transitively_independent_of_template_order() -> void:
	var run: RunController = F.run(true, true)
	for origin: Vector2i in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(4, 0)]: F.place(run, F.X.offsets, origin)
	var first: Array[BoardMatchGroup] = run.state.rules.find_matches()
	var second: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.L, F.X, F.X])
	assert_eq(first.size(), 1)
	assert_eq(first[0].piece_ids.size(), 11)
	assert_eq(second[0].piece_ids, first[0].piece_ids)
	assert_eq(first[0].hits.filter(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"x").size(), 3)

func test_x_is_opt_in_and_mutating_query_copies_keeps_other_runs_and_resource() -> void:
	var run: RunController = F.run()
	var other: RunController = F.run(false)
	F.place(run, F.X.offsets)
	F.place(other, F.X.offsets)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	groups[0].hits[0].coordinates.clear()
	run.state.rules.match_templates()[0].offsets.clear()
	assert_eq(run.state.rules.find_matches()[0].hits[0].coordinates.size(), 5)
	assert_true(other.state.rules.find_matches().is_empty())
	assert_eq(F.X.offsets.size(), 5)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_x_removal_runs_real_fuse_and_sweeper_without_duplicate_targets() -> void:
	for line: bool in [false, true]:
		var run: RunController = F.run()
		F.place(run, F.X.offsets)
		var source: Vector2i = Vector2i(0, 0) if line else Vector2i(2, 2)
		if line:
			run.state.rules.remove_piece(run.state.rules.state.get_piece_id(source))
			run.abilities.add_line_piece(LineClearState.AXIS_ROW, source, 0)
		else:
			assert_true(run.abilities.assign_fuse(run.state.rules.state.get_piece_id(source)))
		var target: PieceState = run.state.rules.place_piece(Vector2i(8, 0) if line else Vector2i(3, 3), 1)
		var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 5)
		assert_eq(results[0].hits[0].shape_id, &"x")
		assert_eq(results[1].cause, &"line_clear" if line else &"explosion")
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].removed[0].piece_id, target.piece_id)
		assert_eq(run.state.rules.state.get_piece_count(), 0)

func test_x_does_not_treat_plus_as_a_forty_five_degree_rotation() -> void:
	var run: RunController = F.run()
	var plus: MatchShapeTemplate = load("res://gameplay/board/matching/plus_template.tres") as MatchShapeTemplate
	F.place(run, plus.offsets)
	assert_true(run.state.rules.find_matches().is_empty())
	var templates: Array[MatchShapeTemplate] = [plus]
	assert_eq(BoardMatchDetector.find_matches(run.state.rules.state, 5, templates)[0].piece_ids.size(), 5)
