extends GutTest

const F: Script = preload("res://tests/support/zs_template_fixture.gd")

func test_zs_matches_confirmed_resource_and_has_four_unique_orientations() -> void:
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)]
	assert_eq(F.ZS.shape_id, &"zs")
	assert_eq(F.ZS.offsets, expected)
	var variants: Array[MatchShapeTemplate] = F.ZS.variants()
	assert_eq(variants.size(), 4)
	var run: RunController = F.run()
	F.place(run, expected, Vector2i(2, 2))
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.ZS, F.ZS])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].hits.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(groups[0].hits[0].shape_id, &"zs")

func test_each_missing_or_wrong_color_cell_and_all_clipped_edges_refuse_zs() -> void:
	for cell: Vector2i in F.ZS.offsets:
		for wrong: bool in [false, true]:
			var run: RunController = F.run()
			F.place(run, F.ZS.offsets, Vector2i.ZERO, 0, cell)
			if wrong: run.state.rules.place_piece(cell, 1)
			assert_true(run.state.rules.find_matches().is_empty())
	for origin: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(7, 0), Vector2i(0, 7)]:
		var run: RunController = F.run()
		for cell: Vector2i in F.ZS.offsets:
			if run.state.rules.state.is_valid_coordinate(origin + cell): run.state.rules.place_piece(origin + cell, 0)
		assert_true(run.state.rules.find_matches().is_empty())

func test_edge_extra_color_neither_blocks_nor_extends_zs() -> void:
	for color: int in [0, 1]:
		var run: RunController = F.run()
		F.place(run, F.ZS.offsets)
		var extra: PieceState = run.state.rules.place_piece(Vector2i(2, 0), color)
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 5)
		assert_false(groups[0].piece_ids.has(extra.piece_id))

func test_long_arm_merges_before_landing_filter_and_scores_union_once() -> void:
	var run: RunController = F.run()
	F.place(run, F.ZS.offsets)
	for axis: int in [3, 4]: run.state.rules.place_piece(Vector2i(axis, axis), 0)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches_at(Vector2i(4, 4))
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"zs"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"line"))
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	assert_eq(run.abilities.resolve(groups)[0].removed.size(), 7)
	assert_eq(run.state.ledger.total, 104)

func test_shared_l_zs_union_and_separate_shapes_keep_distinct_groups() -> void:
	var run: RunController = F.run(true, true)
	F.place(run, F.L.offsets)
	F.place(run, F.ZS.offsets)
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"l"))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"zs"))
	var separate: RunController = F.run(true, true)
	F.place(separate, F.L.offsets)
	F.place(separate, F.ZS.offsets, Vector2i(5, 5))
	groups = separate.state.rules.find_matches()
	assert_eq(groups.size(), 2)
	separate.state.explosion.upgrades[&"precision_reward"] = 1
	assert_eq(separate.abilities.resolve(groups).size(), 2)
	assert_eq(separate.state.ledger.total, 110)

func test_three_zs_placements_create_five_transitively_merged_hits_independent_of_template_order() -> void:
	var run: RunController = F.run(true, true)
	for origin: Vector2i in [Vector2i.ZERO, Vector2i(2, 2), Vector2i(4, 4)]: F.place(run, F.ZS.offsets, origin)
	var first: Array[BoardMatchGroup] = run.state.rules.find_matches()
	var second: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(run.state.rules.state, 5, [F.L, F.ZS, F.ZS])
	assert_eq(first.size(), 1)
	assert_eq(first[0].piece_ids.size(), 13)
	assert_eq(second[0].piece_ids, first[0].piece_ids)
	# Three diagonal placements also complete rotated hits at (1,1) and (3,3).
	assert_eq(first[0].hits.filter(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"zs").size(), 5)
	var expected_origins: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]
	var seen: Array[String] = []
	for hit: BoardMatchHit in first[0].hits:
		if hit.shape_id != &"zs": continue
		assert_true(expected_origins.has(hit.origin))
		assert_false(seen.has(str(hit.piece_ids)))
		seen.append(str(hit.piece_ids))


func test_zs_is_opt_in_and_mutating_query_copies_keeps_other_runs_and_resource() -> void:
	var run: RunController = F.run()
	var other: RunController = F.run(false)
	F.place(run, F.ZS.offsets)
	F.place(other, F.ZS.offsets)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	groups[0].hits[0].coordinates.clear()
	run.state.rules.match_templates()[0].offsets.clear()
	assert_eq(run.state.rules.find_matches()[0].hits[0].coordinates.size(), 5)
	assert_true(other.state.rules.find_matches().is_empty())
	assert_eq(F.ZS.offsets.size(), 5)
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_zs_removal_runs_real_fuse_and_sweeper_without_duplicate_targets() -> void:
	for line: bool in [false, true]:
		var run: RunController = F.run()
		F.place(run, F.ZS.offsets)
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
		assert_eq(results[0].hits[0].shape_id, &"zs")
		assert_eq(results[1].cause, &"line_clear" if line else &"explosion")
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].removed[0].piece_id, target.piece_id)
		assert_eq(run.state.rules.state.get_piece_count(), 0)


func test_all_rotations_and_mirrors_share_one_unlock_identity() -> void:
	for variant: MatchShapeTemplate in F.ZS.variants():
		var run: RunController = F.run(false)
		assert_true(run.state.rules.shape_unlocks.unlock(F.ZS, 1))
		assert_false(run.state.rules.shape_unlocks.unlock(variant, 2))
		F.place(run, variant.offsets, Vector2i(2, 2))
		var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 5)
		assert_eq(groups[0].hits.size(), 1)
		assert_eq(groups[0].hits[0].shape_id, &"zs")
		assert_eq(run.state.rules.shape_unlocks.ids(), [&"zs"])
