extends GutTest

var run: RunController

func before_each() -> void:
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)

func test_t02_core_fuse_chain_scores_70_and_clears() -> void:
	_t02()
	assert_true(run.abilities.upgrade_reward())
	var results: Array[MatchResult] = run.resolve_matches_at(Vector2i(5, 4))
	assert_eq(results.size(), 3)
	assert_eq(results[0].score_entry.final_score, 50)
	assert_eq(results[1].removed.size(), 2)
	assert_eq(results[2].removed.size(), 2)
	assert_eq(results[1].score_entry.extra_score, 10)
	assert_eq(results[2].score_entry.extra_score, 10)
	assert_eq(results[1].generation, 1)
	assert_eq(results[2].generation, 2)
	assert_eq(run.state.ledger.total, 70)
	assert_eq(run.state.rules.state.get_piece_count(), 0)
	assert_eq(run.state.explosion.instances.size(), 0)
	assert_true(run.state.explosion.unlocked)
	assert_eq(run.resolve_all_matches().size(), 0)
	assert_eq(run.state.ledger.total, 70)

func test_t03_overlapping_sources_sort_by_id_and_count_target_once() -> void:
	var source_ids: Array[int] = []
	for x: int in range(1, 6):
		var piece: PieceState = run.state.rules.place_piece(Vector2i(x, 4), 1)
		if x == 3 or x == 5:
			assert_true(run.abilities.assign_fuse(piece.piece_id))
			source_ids.append(piece.piece_id)
	run.state.rules.place_piece(Vector2i(4, 3), 0)
	run.abilities.upgrade_reward()
	run.state.explosion.blast_extra_level = 0
	var results: Array[MatchResult] = run.resolve_matches_at(Vector2i(5, 4))
	assert_eq(results.size(), 3)
	assert_eq(results[1].source_id, source_ids[0])
	assert_eq(results[2].source_id, source_ids[1])
	assert_eq(results[1].removed.size(), 1)
	assert_eq(results[2].removed.size(), 0)
	assert_eq(results[2].score_entry.final_score, 0)
	assert_eq(run.state.ledger.total, 55)

func test_t09_match_multiplier_and_extra_do_not_multiply_blast_extra() -> void:
	_t02()
	run.abilities.upgrade_reward()
	run.state.explosion.multiplier_level = 1
	run.state.explosion.match_extra_level = 3
	run.state.explosion.blast_extra_level = 2
	var results: Array[MatchResult] = run.resolve_all_matches()
	assert_eq(results[0].score_entry.final_score, 90)
	assert_eq(results[1].score_entry.base_score, 0)
	assert_eq(results[1].score_entry.extra_score, 20)
	assert_eq(results[1].score_entry.final_score, 20)
	assert_eq(results[2].score_entry.final_score, 20)
	assert_eq(run.state.ledger.total, 130)

func test_empty_blast_never_awards_blast_extra() -> void:
	for x: int in range(5):
		var piece: PieceState = run.state.rules.place_piece(Vector2i(x, 4), 1)
		if x == 2:
			run.abilities.assign_fuse(piece.piece_id)
	run.state.explosion.blast_extra_level = 4
	var results: Array[MatchResult] = run.resolve_all_matches()
	assert_eq(results.size(), 2)
	assert_eq(results[1].removed.size(), 0)
	assert_eq(results[1].score_entry.extra_score, 0)
	assert_eq(run.state.ledger.total, 50)

func test_core_unique_fuse_eligibility_and_one_instance_per_piece() -> void:
	var core: PieceState = run.abilities.add_core(Vector2i.ZERO)
	assert_not_null(core)
	assert_null(run.abilities.add_core(Vector2i(1, 0)))
	assert_false(run.abilities.assign_fuse(core.piece_id))
	assert_false(run.abilities.assign_fuse(999))
	var ordinary: PieceState = run.state.rules.place_piece(Vector2i(1, 1), 0)
	assert_true(run.abilities.assign_fuse(ordinary.piece_id))
	assert_false(run.abilities.assign_fuse(ordinary.piece_id))
	assert_eq(run.state.explosion.instances.size(), 2)

func test_radius_and_reward_caps_and_shared_definitions_are_isolated() -> void:
	assert_false(run.abilities.upgrade_radius())
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4))
	var second: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	var other: PieceState = second.abilities.add_core(Vector2i(4, 4))
	assert_eq(run.state.explosion.instances[core.piece_id].definition, second.state.explosion.instances[other.piece_id].definition)
	assert_true(run.abilities.upgrade_radius())
	assert_false(run.abilities.upgrade_radius())
	for index: int in range(3):
		assert_true(run.abilities.upgrade_reward())
	assert_false(run.abilities.upgrade_reward())
	assert_eq(second.state.explosion.radius_level, 0)
	assert_eq(second.state.explosion.reward_level, 0)
	assert_eq(run.abilities.config.base_radius, 1)
	assert_false(second.state.explosion.instances[other.piece_id].has_triggered)

func test_board_edge_blast_clips_and_ordinary_green_never_explodes() -> void:
	run.abilities.add_core(Vector2i.ZERO)
	for x: int in range(1, 5):
		run.state.rules.place_piece(Vector2i(x, 0), 1)
	run.state.rules.place_piece(Vector2i(0, 1), 2)
	run.state.rules.place_piece(Vector2i(1, 1), 3)
	var results: Array[MatchResult] = run.resolve_all_matches()
	assert_eq(results.size(), 2)
	assert_eq(results[1].removed.size(), 2)
	assert_eq(results[1].center, Vector2i.ZERO)
	assert_eq(run.state.rules.state.get_piece_count(), 0)

func test_budget_failure_preserves_board_ledger_and_instances() -> void:
	_t02()
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities.config = config
	var count: int = run.state.rules.state.get_piece_count()
	var groups: Array[BoardMatchGroup] = run.state.rules.find_matches()
	assert_eq(run.abilities.resolve(groups).size(), 0)
	assert_false(run.abilities.last_error.is_empty())
	assert_eq(run.state.rules.state.get_piece_count(), count)
	assert_eq(run.state.ledger.total, 0)
	for instance: AbilityInstance in run.state.explosion.instances.values():
		assert_false(instance.has_triggered)

func test_reset_clears_fuses_levels_unlock_and_consumed_events() -> void:
	_t02()
	run.abilities.upgrade_reward()
	run.resolve_all_matches()
	run.state.reset_counters()
	assert_eq(run.state.explosion.instances.size(), 0)
	assert_eq(run.state.explosion.reward_level, 0)
	assert_false(run.state.explosion.unlocked)
	assert_eq(run.state.ledger.get_entries().size(), 0)

func test_birth_budget_fault_stops_batch_and_preserves_error_phase() -> void:
	run = RunController.new(BoardRules.new(BoardState.new(5, 1), 5), 0)
	for x: int in range(4):
		run.state.rules.place_piece(Vector2i(x, 0), 0)
	for run_seed: int in range(1000):
		run.state.spawning.content_random.seed = run_seed
		run.state.random.randi_range(0, 0)
		if run.state.spawning.draw_color(run.state.spawning.content_random) == 0:
			run.state.spawning.content_random.seed = run_seed
			break
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 0
	run.abilities.config = config
	assert_eq(run.spawn_batch().size(), 1)
	assert_eq(run.state.phase, RunState.Phase.ERROR)
	assert_eq(run.state.ledger.total, 0)
	var random_state: int = run.state.random.state
	assert_null(run.spawn_one())
	run.enter_rewards()
	run.end_turn()
	run.start_turn()
	run.finish_game()
	assert_eq(run.state.phase, RunState.Phase.ERROR)
	assert_false(run.state.is_game_over)
	assert_eq(run.state.random.state, random_state)

func _t02() -> void:
	for x: int in range(1, 5):
		run.state.rules.place_piece(Vector2i(x, 4), 1)
	run.abilities.add_core(Vector2i(5, 4))
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(6, 4), 0)
	run.abilities.assign_fuse(fuse.piece_id)
	run.state.rules.place_piece(Vector2i(6, 3), 2)
	run.state.rules.place_piece(Vector2i(7, 4), 3)
	run.state.rules.place_piece(Vector2i(7, 3), 4)
