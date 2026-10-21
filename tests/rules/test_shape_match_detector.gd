extends GutTest

const L: MatchShapeTemplate = preload("res://gameplay/board/matching/l_template.tres")

func _rules() -> BoardRules:
	return BoardRules.new(BoardState.new(9, 9), 5)

func _place(rules: BoardRules, offsets: Array[Vector2i], origin: Vector2i = Vector2i.ZERO) -> void:
	for offset: Vector2i in offsets:
		var coordinate: Vector2i = origin + offset
		if rules.state.is_valid_coordinate(coordinate) and rules.state.get_piece_at(coordinate) == null:
			rules.place_piece(coordinate, 0)

func test_l_is_explicit_prototype_and_default_stays_straight_only() -> void:
	var rules: BoardRules = _rules()
	_place(rules, L.offsets)
	assert_true(rules.find_matches().is_empty())
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(groups[0].hits[0].shape_id, &"l")

func test_rotations_and_mirrors_are_normalized_and_deduplicated() -> void:
	var original: Array[Vector2i] = L.offsets.duplicate()
	var variants: Array[MatchShapeTemplate] = L.variants()
	assert_eq(variants.size(), 4)
	for variant: MatchShapeTemplate in variants:
		var rules: BoardRules = _rules()
		_place(rules, variant.offsets, Vector2i(2, 2))
		var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L, L])
		assert_eq(groups.size(), 1)
		assert_eq(groups[0].hits.size(), 1)
		assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(L.offsets, original)

func test_missing_wrong_color_and_clipped_edges_do_not_match() -> void:
	for missing: int in range(L.offsets.size()):
		for wrong_color: bool in [false, true]:
			var rules: BoardRules = _rules()
			_place(rules, L.offsets)
			var id: int = rules.state.get_piece_id(L.offsets[missing])
			if wrong_color: rules.set_piece_color(id, 1)
			else: rules.remove_piece(id)
			assert_true(BoardMatchDetector.find_matches(rules.state, 5, [L]).is_empty())
	var edge: BoardRules = _rules()
	_place(edge, L.offsets, Vector2i(-1, 0))
	edge.place_piece(Vector2i(8, 0), 0)
	assert_true(BoardMatchDetector.find_matches(edge.state, 5, [L]).is_empty())

func test_extra_same_color_does_not_extend_template() -> void:
	var rules: BoardRules = _rules()
	_place(rules, L.offsets)
	var extra: PieceState = rules.place_piece(Vector2i(1, 0), 0)
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_false(groups[0].piece_ids.has(extra.piece_id))

func test_line_and_l_union_seven_scores_once_and_freezes_geometry() -> void:
	var rules: BoardRules = _rules()
	for x: int in range(5): rules.place_piece(Vector2i(x, 2), 0)
	rules.place_piece(Vector2i(2, 0), 0)
	rules.place_piece(Vector2i(2, 1), 0)
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches_at(rules.state, 5, Vector2i(4, 2), [L])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 7)
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"line" and hit.piece_ids.size() == 5))
	assert_true(groups[0].hits.any(func(hit: BoardMatchHit) -> bool: return hit.shape_id == &"l"))
	var run: RunController = RunController.new(rules, 118)
	run.state.explosion.upgrades[&"precision_reward"] = 1
	run.state.explosion.upgrades[&"longline_reward"] = 1
	var results: Array[MatchResult] = run.abilities.resolve(groups)
	assert_eq(results.size(), 1)
	assert_eq(results[0].removed.size(), 7)
	assert_eq(run.state.ledger.total, 104)
	assert_eq(groups[0].hits[0].coordinates.size(), groups[0].hits[0].piece_ids.size())
	assert_eq(rules.state.get_piece_count(), 0)

func test_transitive_shared_entities_merge_but_adjacency_does_not() -> void:
	var rules: BoardRules = _rules()
	for origin: Vector2i in [Vector2i.ZERO, Vector2i(2, 2), Vector2i(4, 4)]: _place(rules, L.offsets, origin)
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	assert_eq(groups.size(), 1)
	assert_eq(groups[0].piece_ids.size(), 13)
	var adjacent: BoardRules = _rules()
	_place(adjacent, L.offsets)
	_place(adjacent, L.offsets, Vector2i(3, 1))
	groups = BoardMatchDetector.find_matches(adjacent.state, 5, [L])
	assert_eq(groups.size(), 2)
	assert_eq(groups[0].piece_ids.size(), 5)
	assert_eq(groups[1].piece_ids.size(), 5)

func test_query_and_result_mutation_do_not_change_state_or_template() -> void:
	var rules: BoardRules = _rules()
	_place(rules, L.offsets)
	var run: RunController = RunController.new(rules, 118)
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	var first: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
	first[0].hits[0].coordinates[0] = Vector2i(8, 8)
	first[0].piece_ids.clear()
	var second: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	assert_eq(second[0].piece_ids.size(), 5)
	assert_ne(second[0].hits[0].coordinates[0], Vector2i(8, 8))
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)

func test_two_independent_l_groups_receive_quantity_bonus_per_event() -> void:
	var rules: BoardRules = _rules()
	_place(rules, L.offsets)
	_place(rules, L.offsets, Vector2i(5, 5))
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	assert_eq(groups.size(), 2)
	var run: RunController = RunController.new(rules, 118)
	run.state.explosion.upgrades[&"precision_reward"] = 1
	var results: Array[MatchResult] = run.abilities.resolve(groups)
	assert_eq(results.size(), 2)
	assert_eq(run.state.ledger.total, 110)

func test_whole_match_batch_leaves_before_first_blast() -> void:
	var rules: BoardRules = _rules()
	_place(rules, L.offsets)
	_place(rules, L.offsets, Vector2i(3, 1))
	var run: RunController = RunController.new(rules, 118)
	run.state.explosion.upgrades[&"precision_reward"] = 1
	assert_true(run.abilities.assign_fuse(rules.state.get_piece_id(Vector2i(2, 2))))
	var groups: Array[BoardMatchGroup] = BoardMatchDetector.find_matches(rules.state, 5, [L])
	var results: Array[MatchResult] = run.abilities.resolve(groups)
	assert_eq(results.size(), 3)
	assert_eq(results[0].removed.size(), 5)
	assert_eq(results[1].removed.size(), 5)
	assert_eq(results[2].cause, &"explosion")
	assert_true(results[2].removed.is_empty())
	assert_eq(run.state.ledger.total, 110)

func test_invalid_template_is_diagnosed_without_hits_or_state_change() -> void:
	var duplicate: MatchShapeTemplate = MatchShapeTemplate.new()
	duplicate.shape_id = &"l"
	duplicate.offsets = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
	var anonymous: MatchShapeTemplate = MatchShapeTemplate.new()
	anonymous.offsets = L.offsets.duplicate()
	for template: MatchShapeTemplate in [duplicate, anonymous, null]:
		var rules: BoardRules = _rules()
		_place(rules, L.offsets)
		var run: RunController = RunController.new(rules, 118)
		var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
		assert_true(BoardMatchDetector.find_matches(rules.state, 5, [template]).is_empty())
		assert_push_error("invalid match template")
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
