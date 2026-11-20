extends GutTest

class FixedRemoval extends ChoiceEffect:
	var source_id: int
	func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
		var target: SkillTarget = SkillTarget.new()
		target.piece_ids = [source_id]
		return target
	func build(_context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		request.kind = ChoiceEffectRequest.Kind.CLEAR
		request.piece_ids = target.piece_ids.duplicate()
		return request

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	run.abilities.config = run.abilities.config.duplicate() as ExplosionConfig
	run.state.explosion.reward_level = 1
	var f: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 0)
	run.abilities.assign_fuse(f.piece_id)
	run.state.rules.place_piece(Vector2i(4, 3), 1)
	run.state.rules.place_piece(Vector2i(5, 3), 2)
	return run

func _hold(run: RunController, coordinate: Vector2i = Vector2i(3, 3)) -> void:
	var pieces: Array[PieceState] = [run.state.rules.state.get_piece_at(coordinate)]
	run.abilities.resolve_removal(pieces, &"skill_clear", true)

func test_s01_radius_upgrade_does_not_change_queued_blast() -> void:
	var run: RunController = _run()
	_hold(run)
	run.state.explosion.radius_level = 1
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].radius, 1)
	assert_eq(results[0].removed.size(), 1)
	assert_eq(run.state.ledger.total, 5)
	assert_not_null(run.state.rules.state.get_piece_at(Vector2i(5, 3)))

func test_s02_upgrade_before_trigger_affects_new_blast() -> void:
	var run: RunController = _run()
	run.state.explosion.radius_level = 1
	_hold(run)
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].radius, 2)
	assert_eq(results[0].removed.size(), 2)
	assert_eq(run.state.ledger.total, 10)

func test_s03_reward_and_fixed_bonus_freeze_at_trigger() -> void:
	for before: bool in [false, true]:
		var run: RunController = _run()
		if before:
			run.state.explosion.reward_level = 2
			run.state.explosion.blast_extra_level = 1
		_hold(run)
		run.state.explosion.reward_level = 2
		run.state.explosion.blast_extra_level = 1
		run.abilities.flush_held_blasts()
		assert_eq(run.state.ledger.total, 15 if before else 5)

func test_s04_removed_target_is_not_paid_or_revived() -> void:
	var run: RunController = _run()
	_hold(run)
	_hold(run, Vector2i(4, 3))
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].removed.size(), 0)
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.rules.state.get_piece_count(), 1)

func test_s05_new_target_is_selected_at_execution() -> void:
	var run: RunController = _run()
	_hold(run)
	var c: PieceState = run.state.rules.place_piece(Vector2i(3, 4), 3)
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].removed.size(), 2)
	assert_null(run.state.rules.state.get_piece(c.piece_id))
	assert_eq(run.state.ledger.total, 10)

func test_s06_descendant_samples_its_own_new_strength() -> void:
	var run: RunController = _run()
	run.abilities.assign_fuse(run.state.rules.state.get_piece_at(Vector2i(4, 3)).piece_id)
	_hold(run)
	run.state.explosion.reward_level = 2
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results.size(), 2)
	assert_eq(results[0].score_entry.extra_score, 5)
	assert_eq(results[1].score_entry.extra_score, 10)
	assert_eq(run.state.ledger.total, 15)

func test_s08_config_mutation_and_other_run_do_not_change_queued_strength() -> void:
	var run: RunController = _run()
	_hold(run)
	run.abilities.config.base_radius = 3
	run.abilities.config.reward_per_target = 99
	var other: RunController = _run()
	other.state.explosion.reward_level = 3
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].radius, 1)
	assert_eq(run.state.ledger.total, 5)
	assert_eq(other.state.rules.state.get_piece_count(), 3)

func test_line_band_and_score_coefficients_freeze_but_targets_remain_live() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(3, 3), 0)
	run.state.rules.place_piece(Vector2i(6, 3), 1)
	run.state.rules.place_piece(Vector2i(6, 4), 2)
	_hold(run, source.coordinate)
	run.state.line_clear.upgrades[&"line_row_span"] = 1
	run.state.line_clear.upgrades[&"line_clear_score"] = 1
	run.state.explosion.multiplier_level = 2
	run.state.explosion.match_extra_level = 1
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].radius, 0)
	assert_eq(results[0].removed.size(), 1)
	assert_eq(results[0].score_entry.extra_score, 0)
	assert_eq(results[0].score_entry.multiplier, 1.0)
	assert_not_null(run.state.rules.state.get_piece_at(Vector2i(6, 4)))

func test_target_mark_is_live_but_mark_reward_coefficient_is_frozen() -> void:
	var run: RunController = _run()
	run.state.explosion.upgrades[&"marked_reward"] = 1
	_hold(run)
	run.state.explosion.upgrades[&"marked_reward"] = 3
	run.abilities.assign_fuse(run.state.rules.state.get_piece_at(Vector2i(4, 3)).piece_id)
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].score_entry.extra_score, 10)
	assert_eq(results.size(), 2)

func test_source_filter_is_frozen_not_retroactively_installed() -> void:
	var run: RunController = _run()
	run.state.rules.set_piece_color(run.state.rules.state.get_piece_at(Vector2i(4, 3)).piece_id, 0)
	_hold(run)
	run.state.explosion.upgrades[&"selective_blast"] = 1
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results[0].removed.size(), 1)

func test_s07_nested_composite_preserves_trigger_order() -> void:
	for upgrade_first: bool in [false, true]:
		var run: RunController = _run()
		var removal: FixedRemoval = FixedRemoval.new()
		removal.source_id = run.state.rules.state.get_piece_at(Vector2i(3, 3)).piece_id
		var upgrade: DemolitionStatEffect = DemolitionStatEffect.new()
		var inner: CompositeEffect = CompositeEffect.new()
		inner.children = [upgrade if upgrade_first else removal]
		var outer: CompositeEffect = CompositeEffect.new()
		outer.children = [inner, removal if upgrade_first else upgrade]
		var frozen: CompositeSkillTarget = outer.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random)
		var result: SkillApplyResult = SkillApplyResult.new()
		assert_eq(AbilityEffectRunner.apply_skill_effect(run, outer, frozen, result), "")
		assert_eq(result.matches[0].radius, 2 if upgrade_first else 1)
		assert_eq(run.state.ledger.total, 10 if upgrade_first else 5)

func test_snapshot_and_record_distinguish_strength_from_actual_targets() -> void:
	var run: RunController = _run()
	_hold(run)
	var snapshot: Dictionary = RunSnapshot.capture(run)
	assert_eq(snapshot.pending_removals[0].strength.per_target, "5")
	snapshot.pending_removals[0].strength.per_target = "999"
	run.state.explosion.reward_level = 3
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	var events: Array[Dictionary] = RunRecorder.matches(results)
	assert_eq(events[0].trigger_strength.per_target, "5")
	assert_eq(events[0].removed.size(), 1)
	assert_eq(events[0].score.E, "5")
	assert_true(run.abilities.pending_removals().is_empty())
	assert_true(run.abilities.flush_held_blasts().is_empty())
