extends GutTest

const F: Script = preload("res://tests/support/u_template_fixture.gd")

func test_u_resource_is_seven_cells_and_has_four_unique_orientations() -> void:
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
	assert_eq(F.U.shape_id, &"u")
	assert_eq(F.U.offsets, expected)
	assert_eq(F.U.variants().size(), 4)
	var run: RunController = F.run()
	F.place(run, expected)
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.U, F.U])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].hits.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 7)
	assert_eq(run.state.ledger.total, 84)

func test_each_required_cell_and_all_four_clipped_edges_refuse_u() -> void:
	for cell: Vector2i in F.U.offsets:
		for wrong: bool in [false, true]:
			var run: RunController = F.run()
			F.place(run, F.U.offsets, Vector2i.ZERO, 0, cell)
			if wrong: run.state.rules.place_piece(cell, 1)
			assert_true(run.state.rules.find_matches().is_empty())
	for origin: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(7, 0), Vector2i(0, 7)]:
		var run: RunController = F.run()
		for cell: Vector2i in F.U.offsets:
			if run.state.rules.state.is_valid_coordinate(origin + cell): run.state.rules.place_piece(origin + cell, 0)
		assert_true(run.state.rules.find_matches().is_empty())

func test_center_is_not_required_empty_and_does_not_extend_single_u() -> void:
	for color: int in [0, 1]:
		var run: RunController = F.run()
		F.place(run, F.U.offsets)
		var extra: PieceState = run.state.rules.place_piece(Vector2i(1, 1), color)
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 7)
		assert_false(groups[0].piece_ids.has(extra.piece_id))

func test_closed_top_completes_four_rotated_us_and_only_perimeter_is_consumed() -> void:
	for center_present: bool in [false, true]:
		var run: RunController = F.run()
		F.place(run, F.U.offsets)
		run.state.rules.place_piece(Vector2i(1, 0), 0)
		if center_present: run.state.rules.place_piece(Vector2i(1, 1), 0)
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].hits.size(), 4)
		assert_eq(groups[0].piece_ids.size(), 8)
		assert_eq(run.abilities.resolve(groups)[0].removed.size(), 8)
		assert_eq(run.state.ledger.total, 104)
		assert_eq(run.state.rules.state.get_piece_count(), 1 if center_present else 0)

func test_long_arm_and_u_merge_before_landing_filter_and_score_nine_once() -> void:
	var run: RunController = F.run()
	F.place(run, F.U.offsets)
	for y: int in [3, 4]: run.state.rules.place_piece(Vector2i(0, y), 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches_at(Vector2i(0, 4))
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 9)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"u"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"line"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 9)
	assert_eq(run.state.ledger.total, 146)

func test_l_inside_u_is_one_seven_cell_group_and_separate_shapes_score_independently() -> void:
	var run: RunController = F.run(true, true)
	F.place(run, F.U.offsets)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"l"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"u"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(run.abilities.resolve(groups).size(), 1)
	assert_eq(run.state.ledger.total, 84)
	var separate: RunController = F.run(true, true)
	F.place(separate, F.L.offsets)
	F.place(separate, F.U.offsets, Vector2i(5, 5))
	groups = separate.state.rules.find_matches()
	assert_eq(groups.size(), 2)
	separate.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(separate.abilities.resolve(groups).size(), 2)
	assert_eq(separate.state.ledger.total, 139)

func test_three_us_transitively_merge_fifteen_cells_independent_of_template_order() -> void:
	var run: RunController = F.run(true, true)
	for origin: Vector2i in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(4, 0)]: F.place(run, F.U.offsets, origin)
	var first: Array[BoardMatchGroup] = run.state.rules.find_matches()
	var second: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.L, F.U, F.U])
	assert_eq(first.size(), 1)
	assert_eq(first[0].piece_ids.size(), 15)
	assert_eq(second[0].piece_ids, first[0].piece_ids)
	assert_eq(first[0].hits.filter(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"u").size(), 3)

func test_u_is_opt_in_and_query_mutation_keeps_templates_and_other_runs_isolated() -> void:
	var run: RunController = F.run()
	var other: RunController = F.run(false)
	F.place(run, F.U.offsets)
	F.place(other, F.U.offsets)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	groups[0].hits[0].coordinates.clear()
	run.state.rules.match_templates()[0].offsets.clear()
	assert_eq(run.state.rules.find_matches()[0].hits[0].coordinates.size(), 7)
	assert_true(other.state.rules.find_matches().is_empty())
	assert_eq(F.U.offsets.size(), 7)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_u_removal_runs_fuse_and_sweeper_after_seven_targets_leave() -> void:
	for line: bool in [false, true]:
		var run: RunController = F.run()
		F.place(run, F.U.offsets)
		var source: Vector2i = Vector2i(0, 0) if line else Vector2i(2, 2)
		if line:
			run.state.rules.remove_piece(run.state.rules.state.get_piece_id(source))
			run.abilities.add_line_piece(LineClearState.AXIS_ROW, source, 0)
		else: assert_true(run.abilities.assign_fuse(run.state.rules.state.get_piece_id(source)))
		var target: PieceState = run.state.rules.place_piece(Vector2i(8, 0) if line else Vector2i(3, 3), 1)
		var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 7)
		assert_eq(results[0].hits[0].shape_id, &"u")
		assert_eq(results[1].cause, &"line_clear" if line else &"explosion")
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].removed[0].piece_id, target.piece_id)
		assert_eq(run.state.rules.state.get_piece_count(), 0)

func test_all_u_rotations_and_mirrors_keep_one_unlock_identity() -> void:
	for variant: MatchShapeTemplate in F.U.variants():
		var run: RunController = F.run(false)
		assert_true(run.state.rules.shape_unlocks.unlock(F.U, 1))
		assert_false(run.state.rules.shape_unlocks.unlock(variant, 2))
		F.place(run, variant.offsets, Vector2i(2, 2))
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 7)
		assert_eq(groups[0].hits.size(), 1)
		assert_eq(run.state.rules.shape_unlocks.ids(), [&"u"])
