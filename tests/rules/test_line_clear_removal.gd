extends GutTest

func _run() -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 11)

func test_column_removed_in_horizontal_match_sweeps_column_only() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(4, 4), 0)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 4), 0)
	var targets: Array[PieceState] = []
	for y: int in [0, 1, 2, 3, 5]: targets.append(run.state.rules.place_piece(Vector2i(4, y), 1))
	var survivor: PieceState = run.state.rules.place_piece(Vector2i(5, 5), 2)
	var special: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(4, 6), 2)
	var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
	assert_eq(results.size(), 2)
	if results.size() != 2: return
	assert_eq(results.back().cause, &"line_clear")
	assert_eq(results.back().source_id, source.piece_id)
	assert_eq(results.back().removed.size(), 5)
	assert_eq(results.back().score_entry.final_score, 50)
	for target: PieceState in targets: assert_null(run.state.rules.state.get_piece(target.piece_id))
	assert_not_null(run.state.rules.state.get_piece(survivor.piece_id))
	assert_not_null(run.state.rules.state.get_piece(special.piece_id))
	assert_eq(run.state.ledger.total, 100)

func test_row_removed_by_clear_sweeps_row_and_preserves_specials() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(2, 3), 2)
	var target: PieceState = run.state.rules.place_piece(Vector2i(8, 3), 1)
	var off_axis: PieceState = run.state.rules.place_piece(Vector2i(2, 8), 1)
	var core: PieceState = run.abilities.add_core(Vector2i(4, 3), 3)
	var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"skill_clear")
	assert_eq(results.size(), 1)
	if results.size() != 1: return
	assert_eq(results[0].cause, &"line_clear")
	assert_null(run.state.rules.state.get_piece(target.piece_id))
	assert_not_null(run.state.rules.state.get_piece(off_axis.piece_id))
	assert_not_null(run.state.rules.state.get_piece(core.piece_id))

func test_sweep_fuse_explosion_chain_keeps_generation_and_parent_ids() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(4, 4), 0)
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(4, 1), 1)
	run.abilities.assign_fuse(fuse.piece_id)
	run.abilities.upgrade_reward()
	var neighbor: PieceState = run.state.rules.place_piece(Vector2i(5, 1), 2)
	var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"skill_clear")
	assert_eq(results.size(), 2)
	if results.size() != 2: return
	assert_eq(results[0].cause, &"line_clear")
	assert_eq(results[0].line_axis, LineClearState.AXIS_COLUMN)
	assert_eq(results[1].cause, &"explosion")
	assert_eq(results[1].generation, 2)
	assert_eq(results[1].score_entry.final_score, 5)
	assert_null(run.state.rules.state.get_piece(neighbor.piece_id))
	var traces: Array[Dictionary] = run.state.ability_events.take_traces()
	assert_eq(traces.size(), 2)
	assert_eq(traces[1].cause, &"line_clear")
	assert_eq(traces[1].parent_event_id, traces[0].event_id)
	assert_eq(traces[1].source_ability_id, &"on_eliminated_line_sweep")
	assert_eq(DemolitionRules.action(run.state).effective_blasts, 1)

func test_explosion_removes_sweeper_then_sweeps_from_frozen_coordinate() -> void:
	var run: RunController = _run()
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4), 0)
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(4, 5), 1)
	var distant: PieceState = run.state.rules.place_piece(Vector2i(0, 5), 2)
	var results: Array[MatchResult] = run.abilities.resolve_removal([core], &"consume")
	assert_eq(results.size(), 2)
	if results.size() != 2: return
	assert_eq(results[1].cause, &"line_clear")
	assert_eq(results[1].generation, 2)
	assert_eq(results[1].center, source.coordinate)
	assert_null(run.state.rules.state.get_piece(distant.piece_id))
	assert_eq(run.state.line_clear.instances.size(), 0)

func test_overlapping_sweeps_remove_and_score_each_target_once_in_source_order() -> void:
	var run: RunController = _run()
	var first: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(0, 4), 0)
	var second: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(8, 4), 1)
	for x: int in range(1, 7): run.state.rules.place_piece(Vector2i(x, 4), x % 5)
	var results: Array[MatchResult] = run.abilities.resolve_removal([second, first], &"skill_clear")
	assert_eq(results.size(), 2)
	if results.size() != 2: return
	assert_eq(results[0].source_id, first.piece_id)
	assert_eq(results[0].removed.size(), 6)
	assert_eq(results[0].score_entry.final_score, 66)
	assert_eq(results[1].removed.size(), 0)
	assert_eq(results[1].score_entry.final_score, 0)
	assert_eq(run.state.ledger.total, 66)
	assert_eq(run.state.ability_events.take_traces().size(), 2)
	assert_eq(run.abilities.resolve_removal([first, second], &"skill_clear").size(), 0)
	assert_eq(run.state.ledger.total, 66)

func test_empty_sweep_consumes_once_without_score_or_action_cost() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i.ZERO, 0)
	var instance: AbilityInstance = run.state.line_clear.instances[source.piece_id]
	run.state.explosion.match_extra_level = 4
	var batches: Dictionary = run.state.spawning.refill_batches.duplicate()
	var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"match")
	assert_eq(results.size(), 1)
	assert_eq(instance.trigger_count, 1)
	assert_eq(instance.pending_event_id, 0)
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.action_id, 0)
	assert_eq(run.state.turn_count, 0)
	assert_eq(run.state.spawning.refill_batches, batches)

func test_budget_rejects_before_score_occupancy_or_event_mutation() -> void:
	var run: RunController = _run()
	run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i.ZERO, 0)
	for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 0), 0)
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities.config = config
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_eq(run.abilities.resolve(run.state.rules.find_matches()).size(), 0)
	assert_true(run.abilities.last_error.contains("budget"))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_held_sweep_waits_for_later_leaf_and_uses_frozen_source() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(2, 3), 0)
	var target: PieceState = run.state.rules.place_piece(Vector2i(5, 3), 1)
	var instance: AbilityInstance = run.state.line_clear.instances[source.piece_id]
	assert_eq(run.abilities.resolve_removal([source], &"skill_clear", true).size(), 0)
	assert_not_null(run.state.rules.state.get_piece(target.piece_id))
	assert_eq(instance.trigger_count, 0)
	source.coordinate = Vector2i(2, 8)
	var later: PieceState = run.state.rules.place_piece(Vector2i(8, 3), 3)
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results.size(), 1)
	assert_eq(results[0].center, Vector2i(2, 3))
	assert_null(run.state.rules.state.get_piece(target.piece_id))
	assert_null(run.state.rules.state.get_piece(later.piece_id))
	assert_eq(instance.trigger_count, 1)
	assert_eq(run.abilities.flush_held_blasts().size(), 0)

func test_shared_definition_counts_are_isolated_and_snapshot_records_sweeper() -> void:
	var a: RunController = _run()
	var b: RunController = _run()
	var source_a: PieceState = a.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i.ZERO, 0)
	var source_b: PieceState = b.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i.ZERO, 0)
	var instance_a: AbilityInstance = a.state.line_clear.instances[source_a.piece_id]
	var instance_b: AbilityInstance = b.state.line_clear.instances[source_b.piece_id]
	assert_same(instance_a.definition, instance_b.definition)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(b))
	a.abilities.resolve_removal([source_a], &"match")
	assert_eq(instance_a.trigger_count, 1)
	assert_eq(instance_b.trigger_count, 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(b)), before)
	var snapshot: Dictionary = RunSnapshot.capture(b)
	assert_eq(snapshot.instances[0].ability, "on_eliminated_line_sweep")
	assert_eq(RunSnapshot.config(b).line_trigger.parameters.effect.parameters, {})

func test_sweep_at_end_of_blast_queue_does_not_drop_aftershock() -> void:
	var run: RunController = _run()
	run.state.action_id = 1
	run.state.rule_action_id = 1
	run.state.explosion.upgrades[&"blast_aftershock"] = 1
	var core: PieceState = run.abilities.add_core(Vector2i(4, 4), 0)
	run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(4, 5), 2)
	run.state.rules.place_piece(Vector2i(4, 0), 3)
	var results: Array[MatchResult] = run.abilities.resolve_removal([core], &"consume")
	assert_eq(results.size(), 3)
	if results.size() != 3: return
	assert_eq(results[1].cause, &"line_clear")
	assert_eq(results[2].score_entry.ability_id, &"blast_aftershock")
	assert_true(DemolitionRules.action(run.state).aftershock_used)

func test_score_uses_global_multiplier_and_extra_without_five_match_upgrades() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i.ZERO, 0)
	for x: int in range(1, 6): run.state.rules.place_piece(Vector2i(x, 0), 1)
	run.state.explosion.multiplier_level = 1
	run.state.explosion.match_extra_level = 2
	run.state.explosion.upgrades[&"precision_reward"] = 3
	var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"skill_clear")
	assert_eq(results.size(), 1)
	if results.size() != 1: return
	assert_eq(results[0].score_entry.base_score, 50)
	assert_eq(results[0].score_entry.multiplier, 1.2)
	assert_eq(results[0].score_entry.extra_score, 20)
	assert_eq(results[0].score_entry.final_score, 80)

func test_identical_fixture_results_records_and_snapshots_are_deterministic() -> void:
	var outputs: Array[String] = []
	for index: int in range(2):
		var run: RunController = _run()
		var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(4, 4), 0)
		var fuse: PieceState = run.state.rules.place_piece(Vector2i(4, 0), 1)
		run.abilities.assign_fuse(fuse.piece_id)
		run.state.rules.place_piece(Vector2i(5, 0), 2)
		var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"consume")
		var frozen: Array[PresentationStep] = PlaybackPlanBuilder.matches(results)
		assert_false(frozen.is_empty(), run.abilities.last_error)
		if frozen.is_empty(): return
		assert_eq(frozen[0].matches[0].line_axis, LineClearState.AXIS_COLUMN)
		outputs.append(RunSnapshot.canonical({"snapshot": RunSnapshot.capture(run), "matches": RunRecorder.matches(results), "traces": run.state.ability_events.take_traces()}))
	assert_eq(outputs[0], outputs[1])

func test_line_arrival_budget_includes_new_innate_source_before_skill_commit() -> void:
	var run: RunController = _run()
	run.state.pending_rewards = 1
	run.enter_rewards()
	var skill: SkillDefinition = preload("res://gameplay/progression/content/line_column_drop.tres")
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 1
	offer.reward_id = 1
	offer.choices = [skill]
	var target: SkillTarget = SkillRules.freeze_target(run.state, skill, run.state.rewards.target_random)
	target.coordinate = Vector2i(4, 4)
	target.color = 0
	offer.targets[skill.skill_id] = target
	run.state.rewards.active_offer = offer
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 4), 0)
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities.config = config
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert_false(result.success)
	assert_true(result.error.contains("budget"))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_moving_sweeper_into_five_costs_only_parent_action_and_duplicate_command_is_noop() -> void:
	var run: RunController = _run()
	var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(4, 5), 0)
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 4), 0)
	var target: PieceState = run.state.rules.place_piece(Vector2i(4, 0), 1)
	run.state.phase = RunState.Phase.INPUT
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = source.piece_id
	command.target = Vector2i(4, 4)
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted, result.reason)
	assert_eq(result.turn.matches.size(), 2)
	assert_null(run.state.rules.state.get_piece(target.piece_id))
	assert_eq(run.state.action_id, 1)
	assert_eq(run.state.valid_moves, 1)
	assert_eq(run.state.activations, 0)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), result)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
