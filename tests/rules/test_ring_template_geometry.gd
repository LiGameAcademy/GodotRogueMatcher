extends GutTest

const F: Script = preload("res://tests/support/ring_template_fixture.gd")

func test_ring_resource_is_eight_cells_and_has_one_unique_orientations() -> void:
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
	assert_eq(F.RING.shape_id, &"ring")
	assert_eq(F.RING.offsets, expected)
	assert_eq(F.RING.variants().size(), 1)
	var run: RunController = F.run()
	F.place(run, expected)
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.RING, F.RING])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].hits.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 8)
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 8)
	assert_eq(run.state.ledger.total, 104)

func test_each_required_cell_and_all_four_clipped_edges_refuse_u() -> void:
	for cell: Vector2i in F.RING.offsets:
		for wrong: bool in [false, true]:
			var run: RunController = F.run()
			F.place(run, F.RING.offsets, Vector2i.ZERO, 0, cell)
			if wrong: run.state.rules.place_piece(cell, 1)
			assert_true(run.state.rules.find_matches().is_empty())
	for origin: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(7, 0), Vector2i(0, 7)]:
		var run: RunController = F.run()
		for cell: Vector2i in F.RING.offsets:
			if run.state.rules.state.is_valid_coordinate(origin + cell): run.state.rules.place_piece(origin + cell, 0)
		assert_true(run.state.rules.find_matches().is_empty())

func test_center_is_not_required_empty_and_does_not_extend_single_u() -> void:
	for color: int in [0, 1]:
		var run: RunController = F.run()
		F.place(run, F.RING.offsets)
		var extra: PieceState = run.state.rules.place_piece(Vector2i(1, 1), color)
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 8)
		assert_false(groups[0].piece_ids.has(extra.piece_id))
		assert_eq(run.abilities.resolve(groups)[0].removed.size(), 8)
		assert_eq(run.state.rules.state.get_piece_at(Vector2i(1, 1)).piece_id, extra.piece_id)

func test_missing_top_cell_is_not_a_ring_but_can_be_a_separately_enabled_u() -> void:
	for enabled: bool in [false, true]:
		var run: RunController = F.run(true, enabled)
		F.place(run, F.RING.offsets, Vector2i.ZERO, 0, Vector2i(1, 0))
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1 if enabled else 0)
		if enabled:
			assert_eq(groups[0].piece_ids.size(), 7)
			assert_true(groups[0].hits.all(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"u"))

func test_long_arm_and_ring_merge_before_landing_filter_and_score_nine_once() -> void:
	var run: RunController = F.run()
	F.place(run, F.RING.offsets)
	for y: int in [3, 4]: run.state.rules.place_piece(Vector2i(0, y), 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches_at(Vector2i(0, 4))
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 10)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"ring"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"line"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 10)
	assert_eq(run.state.ledger.total, 170)

func test_u_inside_ring_is_one_seven_cell_group_and_separate_shapes_score_independently() -> void:
	var run: RunController = F.run(true, true)
	F.place(run, F.RING.offsets)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 8)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"u"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"ring"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(run.abilities.resolve(groups).size(), 1)
	assert_eq(run.state.ledger.total, 104)
	var separate: RunController = F.run(true, true)
	F.place(separate, F.U.offsets)
	F.place(separate, F.RING.offsets, Vector2i(5, 5))
	groups = separate.state.rules.find_matches()
	assert_eq(groups.size(), 2)
	separate.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(separate.abilities.resolve(groups).size(), 2)
	assert_eq(separate.state.ledger.total, 188)

func test_three_rings_transitively_merge_eighteen_cells_independent_of_template_order() -> void:
	var run: RunController = F.run(true, true)
	for origin: Vector2i in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(4, 0)]: F.place(run, F.RING.offsets, origin)
	var first: Array[BoardMatchGroup] = run.state.rules.find_matches()
	var second: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.U, F.RING, F.RING])
	assert_eq(first.size(), 1)
	assert_eq(first[0].piece_ids.size(), 18)
	assert_eq(second[0].piece_ids, first[0].piece_ids)
	assert_eq(first[0].hits.filter(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"ring").size(), 3)

func test_ring_is_opt_in_and_query_mutation_keeps_templates_and_other_runs_isolated() -> void:
	var run: RunController = F.run()
	var other: RunController = F.run(false)
	F.place(run, F.RING.offsets)
	F.place(other, F.RING.offsets)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	groups[0].hits[0].coordinates.clear()
	run.state.rules.match_templates()[0].offsets.clear()
	assert_eq(run.state.rules.find_matches()[0].hits[0].coordinates.size(), 8)
	assert_true(other.state.rules.find_matches().is_empty())
	assert_eq(F.RING.offsets.size(), 8)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_ring_removal_runs_fuse_and_sweeper_after_seven_targets_leave() -> void:
	for line: bool in [false, true]:
		var run: RunController = F.run()
		F.place(run, F.RING.offsets)
		var source: Vector2i = Vector2i(0, 0) if line else Vector2i(2, 2)
		if line:
			run.state.rules.remove_piece(run.state.rules.state.get_piece_id(source))
			run.abilities.add_line_piece(LineClearState.AXIS_ROW, source, 0)
		else: assert_true(run.abilities.assign_fuse(run.state.rules.state.get_piece_id(source)))
		var target: PieceState = run.state.rules.place_piece(Vector2i(8, 0) if line else Vector2i(3, 3), 1)
		var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 8)
		assert_eq(results[0].hits[0].shape_id, &"ring")
		assert_eq(results[1].cause, &"line_clear" if line else &"explosion")
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].removed[0].piece_id, target.piece_id)
		assert_eq(run.state.rules.state.get_piece_count(), 0)

func test_all_ring_rotations_and_mirrors_keep_one_unlock_identity() -> void:
	for variant: MatchShapeTemplate in F.RING.variants():
		var run: RunController = F.run(false)
		assert_true(run.state.rules.shape_unlocks.unlock(F.RING, 1))
		assert_false(run.state.rules.shape_unlocks.unlock(variant, 2))
		F.place(run, variant.offsets, Vector2i(2, 2))
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 8)
		assert_eq(groups[0].hits.size(), 1)
		assert_eq(run.state.rules.shape_unlocks.ids(), [&"ring"])
