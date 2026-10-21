extends GutTest

var original_plant_count: int

func before_each() -> void:
	original_plant_count = DemolitionRules.CONFIG.plant_count

func after_each() -> void:
	var template: DemolitionConfig = DemolitionRules.CONFIG
	template.plant_count = original_plant_count

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
	run.state.action_id = 1
	run.state.rule_action_id = 1
	run.state.phase = RunState.Phase.MOVING
	for x: int in range(1, 6): run.state.rules.place_piece(Vector2i(x, 3), 0)
	run.state.rules.place_piece(Vector2i(1, 4), 1)
	run.state.rules.place_piece(Vector2i(2, 4), 2)
	return run

func _hold(run: RunController) -> void:
	assert_eq(run.abilities.resolve(run.state.rules.find_matches(), true).size(), 1)

func test_match_plant_freezes_configuration_at_trigger() -> void:
	var run: RunController = _run()
	run.state.explosion.upgrades[&"fuse_match_plant"] = 1
	_hold(run)
	# Controlled corruption injection; after_each always restores the shared template.
	var template: DemolitionConfig = DemolitionRules.CONFIG
	template.plant_count = original_plant_count + 1
	run.abilities.flush_held_blasts()
	assert_eq(run.state.explosion.instances.size(), original_plant_count)

func test_match_dye_freezes_target_count_before_later_upgrade() -> void:
	var run: RunController = _run()
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	_hold(run)
	run.state.dye.upgrades[&"dye_target_up"] = 2
	run.abilities.flush_held_blasts()
	assert_eq(run.state.dye.dyed_ids.size(), DyeRules.CONFIG.base_targets)
	assert_eq(run.state.dye.waves_used, 1)

func test_match_dye_eligibility_is_not_granted_or_revoked_retroactively() -> void:
	for owned: bool in [false, true]:
		var run: RunController = _run()
		if owned: run.state.dye.upgrades[&"match_dye_echo"] = 1
		_hold(run)
		run.state.dye.upgrades[&"match_dye_echo"] = 0 if owned else 1
		run.abilities.flush_held_blasts()
		assert_eq(run.state.dye.dyed_ids.size(), 1 if owned else 0)

func test_match_dye_freezes_wave_limit_and_keeps_shared_usage() -> void:
	var run: RunController = _run()
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	run.state.dye.begin_root(1)
	run.state.dye.waves_used = 1
	run.state.dye.allow_chain = true
	_hold(run)
	run.state.dye.allow_chain = false
	run.state.dye.upgrades[&"dye_chain_depth"] = 1
	run.abilities.flush_held_blasts()
	assert_eq(run.state.dye.dyed_ids.size(), 0)
	assert_eq(run.state.dye.waves_used, 1)

func test_s08_pending_projection_is_detached_and_retirement_records_interruption() -> void:
	var run: RunController = _run()
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	run.state.explosion.upgrades[&"fuse_match_plant"] = 1
	var matches: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches(), true)
	assert_eq(matches.size(), 1)
	var projection: Dictionary = RunSnapshot.capture(run)
	assert_eq(projection.pending_followups.size(), 2)
	projection.pending_followups[0].count = "999"
	var other: RunController = _run()
	var before: String = RunSnapshot.canonical(RunSnapshot.capture(other))
	run.retire()
	run.retire()
	assert_true(run.abilities.pending_followups().is_empty())
	assert_true(run.abilities.flush_held_blasts().is_empty())
	for trace: Dictionary in matches[0].followups:
		assert_eq(trace.status, "interrupted")
		assert_true(trace.actual_ids.is_empty())
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(other)), before)

func test_s08_dye_trace_keeps_frozen_count_and_actual_surviving_target() -> void:
	var run: RunController = _run()
	run.state.dye.upgrades[&"match_dye_echo"] = 1
	var matches: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches(), true)
	var removed_id: int = run.state.rules.state.get_piece_at(Vector2i(1, 4)).piece_id
	run.state.rules.remove_piece(removed_id)
	var added: PieceState = run.state.rules.place_piece(Vector2i(4, 4), 2)
	run.state.dye.upgrades[&"dye_target_up"] = 2
	var results: Array[MatchResult] = run.abilities.flush_held_blasts()
	assert_eq(results.size(), 1)
	assert_eq(results[0].recolored.size(), 1)
	assert_false(results[0].recolored[0].piece_id == removed_id)
	assert_false(results[0].recolored[0].piece_id == added.piece_id)
	var trace: Dictionary = RunRecorder.matches(matches)[0].followups[0]
	assert_eq(trace.target_count, "1")
	assert_eq(trace.status, "applied")
	assert_eq(trace.actual_ids, [str(results[0].recolored[0].piece_id)])
	assert_eq(trace.source_score_event_id, str(matches[0].score_entry.event_id))

func test_match_plant_eligibility_freezes_but_targets_remain_live() -> void:
	for owned: bool in [false, true]:
		var run: RunController = _run()
		if owned: run.state.explosion.upgrades[&"fuse_match_plant"] = 1
		_hold(run)
		run.state.explosion.upgrades[&"fuse_match_plant"] = 0 if owned else 1
		var id: int = run.state.rules.state.get_piece_at(Vector2i(1, 4)).piece_id
		run.state.rules.remove_piece(id)
		run.abilities.flush_held_blasts()
		assert_eq(run.state.explosion.instances.size(), 1 if owned else 0)
		assert_false(run.state.explosion.instances.has(id))

func test_s08_recorded_dye_command_replays_disk_and_restores_prefix_repeatedly() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_dye")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "fixture", false)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(4, 6))
	command.target = Vector2i(4, 4)
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	assert_false(result.turn.matches[0].followups.is_empty())
	for step: int in range(20):
		if run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS, RunState.Phase.FINISHED]: break
		run.advance()
	var prefix: Array[Dictionary] = run.recorder.records.duplicate(true)
	var expected: String = RunSnapshot.canonical(RunSnapshot.capture(run))
	for repeat: int in range(2):
		var restored: RuleReplay = RuleReplay.new()
		assert_true(restored.restore_prefix(prefix), restored.error)
		assert_eq(RunSnapshot.canonical(RunSnapshot.capture(restored.run)), expected)
		assert_eq(restored.run.state.ledger.total, 105)
		assert_true(restored.run.abilities.pending_followups().is_empty())
		restored.run.retire()
	assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), expected)
	run.recorder.finish(run, "abandoned", "s08")
	var path: String = "user://s08-record.jsonl"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null: return
	for row: Dictionary in run.recorder.records: file.store_line(JSON.stringify(row))
	file.close()
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(path), replay.error)
	assert_eq(replay.checked_records, run.recorder.records.size())
	assert_eq(replay.run.state.ledger.total, 105)


class FaultResolver extends AbilityResolver:
	func _resolve_line_sweep(_event: BlastRequest, _queue: Array[BlastRequest]) -> MatchResult:
		_event_error("injected line failure")
		return MatchResult.new()

func test_fault_cancels_match_dye_bridge_and_remaining_local_tickets() -> void:
	for held: bool in [false, true]:
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 135)
		run.state.action_id = 1
		run.state.rule_action_id = 1
		run.state.phase = RunState.Phase.MOVING
		run.state.dye.upgrades[&"match_dye_echo"] = 1
		run.state.dye.upgrades[&"blast_dye"] = 1
		var first: PieceState = run.state.rules.place_piece(Vector2i(1, 3), 0)
		run.abilities.assign_fuse(first.piece_id)
		run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(2, 3), 0)
		var third: PieceState = run.state.rules.place_piece(Vector2i(3, 3), 0)
		run.abilities.assign_fuse(third.piece_id)
		for x: int in range(4, 6): run.state.rules.place_piece(Vector2i(x, 3), 0)
		run.state.rules.place_piece(Vector2i(1, 4), 1)
		var edge: PieceState = run.state.rules.place_piece(Vector2i(1, 5), 2)
		run.abilities = FaultResolver.new(run.state)
		var results: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches(), held)
		if held: results.append_array(run.abilities.flush_held_blasts())
		assert_eq(run.state.phase, RunState.Phase.ERROR)
		assert_eq(run.state.rules.state.get_piece(edge.piece_id).match_color, 2)
		assert_eq(run.state.dye.waves_used, 0)
		assert_true(run.abilities.pending_followups().is_empty())
		var interrupted: int = 0
		for result: MatchResult in results:
			for trace: Dictionary in result.followups:
				assert_eq(trace.status, "interrupted")
				interrupted += 1
		assert_eq(interrupted, 2)
		var traces: Array[Dictionary] = run.state.ability_events.take_traces()
		assert_true(traces.any(func(trace: Dictionary) -> bool: return trace.owner_id == third.piece_id and trace.get("interruption_reason", "") == &"composite_aborted"))
