extends GutTest

const F: Script = preload("res://tests/support/t_template_fixture.gd")

func test_t_resource_matches_confirmed_five_cell_template() -> void:
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)]
	assert_eq(F.T.shape_id, &"t")
	assert_eq(F.T.offsets, expected)
	var run: RunController = F.run()
	F.place(run, expected)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(groups[0].hits.size(), 1)
	assert_eq(groups[0].hits[0].shape_id, &"t")

func test_t_rotations_and_mirrors_produce_four_unique_hits() -> void:
	var variants: Array[MatchShapeTemplate] = F.T.variants()
	assert_eq(variants.size(), 4)
	for variant: MatchShapeTemplate in variants:
		var run: RunController = F.run()
		F.place(run, variant.offsets, Vector2i(2, 2))
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].hits.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 5)
		for coordinate: Vector2i in groups[0].hits[0].coordinates:
			assert_true(variant.offsets.has(coordinate - Vector2i(2, 2)))

func test_each_missing_or_wrong_color_cell_and_clipped_edge_refuse_t() -> void:
	for cell: Vector2i in F.T.offsets:
		for wrong: bool in [false, true]:
			var run: RunController = F.run()
			F.place(run, F.T.offsets, Vector2i.ZERO, 0, cell)
			if wrong: run.state.rules.place_piece(cell, 1)
			assert_true(run.state.rules.find_matches().is_empty())
	for origin: Vector2i in [Vector2i(-1, 0), Vector2i(7, 7)]:
		var run: RunController = F.run()
		for cell: Vector2i in F.T.offsets:
			if run.state.rules.state.is_valid_coordinate(origin + cell): run.state.rules.place_piece(origin + cell, 0)
		run.state.rules.place_piece(Vector2i(8, 0), 0)
		assert_true(run.state.rules.find_matches().is_empty())

func test_extra_same_color_does_not_extend_t_without_another_hit() -> void:
	var run: RunController = F.run()
	F.place(run, F.T.offsets)
	var extra: PieceState = run.state.rules.place_piece(Vector2i(0, 1), 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_false(groups[0].piece_ids.has(extra.piece_id))

func test_long_stem_and_t_merge_before_landing_filter_and_score_union_once() -> void:
	var run: RunController = F.run()
	F.place(run, F.T.offsets)
	for y: int in [3, 4]: run.state.rules.place_piece(Vector2i(1, y), 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches_at(Vector2i(1, 4))
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"t"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"line"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	var results: Array[MatchResult] = run.abilities.resolve(groups)
	assert_eq(results.size(), 1)
	assert_eq(results[0].removed.size(), 7)
	assert_eq(run.state.ledger.total, 104)

func test_shared_l_and_t_are_one_union_independent_shapes_remain_two_events() -> void:
	var run: RunController = F.run(true, true)
	F.place(run, F.L.offsets)
	F.place(run, F.T.offsets, Vector2i(0, 2))
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"l"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"t"))
	var separate: RunController = F.run(true, true)
	F.place(separate, F.L.offsets)
	F.place(separate, F.T.offsets, Vector2i(5, 5))
	groups = separate.state.rules.find_matches()
	assert_eq(groups.size(), 2)
	separate.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(separate.abilities.resolve(groups).size(), 2)
	assert_eq(separate.state.ledger.total, 110)

func test_overlapping_t_hits_transitively_merge_and_template_order_is_irrelevant() -> void:
	var run: RunController = F.run(true, true)
	for origin: Vector2i in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(4, 0)]: F.place(run, F.T.offsets, origin)
	var first: Array[BoardMatchGroup] = run.state.rules.find_matches()
	var second: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.L, F.T, F.T])
	assert_eq(first.size(), 1)
	assert_eq(first[0].piece_ids.size(), 13)
	assert_eq(second[0].piece_ids, first[0].piece_ids)
	assert_eq(first[0].hits.filter(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"t").size(), 3)

func test_t_is_opt_in_and_query_snapshots_cannot_mutate_template_or_other_runs() -> void:
	var run: RunController = F.run()
	var other: RunController = F.run(false)
	F.place(run, F.T.offsets)
	F.place(other, F.T.offsets)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	groups[0].hits[0].coordinates.clear()
	run.state.rules.match_templates()[0].offsets.clear()
	assert_eq(run.state.rules.find_matches()[0].hits[0].coordinates.size(), 5)
	assert_true(other.state.rules.find_matches().is_empty())
	assert_eq(F.T.offsets.size(), 5)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_t_removal_triggers_existing_fuse_and_sweeper_without_duplicate_targets() -> void:
	for line: bool in [false, true]:
		var run: RunController = F.run()
		F.place(run, F.T.offsets)
		var source: Vector2i = Vector2i(1, 0) if line else Vector2i(1, 2)
		if line:
			run.state.rules.remove_piece(run.state.rules.state.get_piece_id(source))
			run.abilities.add_line_piece(LineClearState.AXIS_ROW, source, 0)
		else:
			assert_true(run.abilities.assign_fuse(run.state.rules.state.get_piece_id(source)))
		var target: PieceState = run.state.rules.place_piece(Vector2i(8, 0) if line else Vector2i(0, 3), 1)
		var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 5)
		assert_eq(results[0].hits[0].shape_id, &"t")
		assert_eq(results[1].cause, &"line_clear" if line else &"explosion")
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].removed[0].piece_id, target.piece_id)
		assert_eq(run.state.rules.state.get_piece_count(), 0)
