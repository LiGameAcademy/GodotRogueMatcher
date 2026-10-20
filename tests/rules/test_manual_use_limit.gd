extends GutTest

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)
	func close() -> TelemetryWriteResult:
		return flush()

func _run(fixture: String = "") -> RunController:
	var config: StageConfig = StageConfig.new()
	config.targets = [10000]
	config.pressure_intervals = [4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	if fixture.is_empty(): run.start_turn()
	else: run.initialize(fixture)
	return run

func _command(run: RunController, piece: PieceState, line: bool = true) -> RunCommand:
	if line:
		var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
		command.piece_id = piece.piece_id
		return command
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = piece.piece_id
	return command

func _finish(run: RunController) -> void:
	for step: int in range(5):
		if run.state.phase == RunState.Phase.INPUT or run.state.is_game_over: return
		run.advance()

func _digest(run: RunController) -> String:
	var snapshot: Dictionary = RunSnapshot.capture(run)
	snapshot.erase("last_command")
	return RunSnapshot.digest(snapshot)

func test_row_column_share_three_uses_duplicate_and_fourth_do_not_consume() -> void:
	var run: RunController = _run("fixture_manual_limit")
	var ids: Array[int] = []
	for position: Vector2i in [Vector2i(0, 0), Vector2i(0, 2), Vector2i(4, 4), Vector2i(0, 6)]:
		ids.append(run.state.rules.state.get_piece_id(position))
	for index: int in range(3):
		var command: RunCommand = _command(run, run.state.rules.state.get_piece(ids[index]))
		var outcome: CommandResult = run.execute_command(command)
		assert_true(outcome.accepted, outcome.reason)
		assert_eq(ManualActivationRules.remaining(run.state, true), 2 - index)
		var snapshot: String = _digest(run)
		assert_same(run.execute_command(command), outcome)
		assert_eq(_digest(run), snapshot)
		_finish(run)
	var source: PieceState = run.state.rules.state.get_piece(ids[3])
	assert_not_null(source)
	var before: String = _digest(run)
	assert_eq(run.execute_command(_command(run, source)).reason, "manual_uses_exhausted")
	assert_eq(_digest(run), before)
	assert_eq(run.state.activations, 3)
	assert_not_null(run.state.rules.state.get_piece(ids[3]))
	assert_eq(RuleBot.new().legal_line_activations(run).size(), 0)
	# Exhausting the manual card does not disable the source's removal ability.
	var passive: Array[MatchResult] = run.abilities.resolve_removal([source], &"match")
	assert_eq(passive.size(), 1)
	assert_gt(passive[0].removed.size(), 0)
	assert_eq(run.state.manual_uses_used[ManualActivationRules.LINE.skill_id], 3)

func test_core_has_independent_three_uses_empty_costs_once_and_passive_survives() -> void:
	var run: RunController = _run()
	run.state.explosion.upgrades[ManualActivationRules.CORE.skill_id] = 1
	run.state.manual_uses_used[ManualActivationRules.LINE.skill_id] = 3
	for index: int in range(3):
		var coordinate: Vector2i = run.state.rules.state.get_empty_coordinates()[0]
		var source: PieceState = run.abilities.add_core(coordinate, 0)
		var command: RunCommand = _command(run, source, false)
		assert_true(run.execute_command(command).accepted)
		assert_eq(ManualActivationRules.remaining(run.state, false), 2 - index)
		assert_true(run.execute_command(command).accepted)
		assert_eq(ManualActivationRules.remaining(run.state, false), 2 - index)
		if index == 0: assert_eq(run.state.ledger.total, 0, "Empty activation consumes a use without a score award")
		_finish(run)
	var source: PieceState = run.abilities.add_core(run.state.rules.state.get_empty_coordinates()[0], 0)
	var before: String = _digest(run)
	assert_eq(run.execute_command(_command(run, source, false)).reason, "manual_uses_exhausted")
	assert_eq(_digest(run), before)
	assert_eq(RuleBot.new().legal_detonations(run).size(), 0)
	run.abilities.resolve_removal([source], &"match")
	assert_null(run.state.rules.state.get_piece(source.piece_id))
	assert_eq(run.state.manual_uses_used[ManualActivationRules.CORE.skill_id], 3)

func test_empty_sweep_costs_once_and_invalid_budget_and_stale_do_not() -> void:
	var run: RunController = _run()
	run.state.line_clear.upgrades[ManualActivationRules.LINE.skill_id] = 1
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i.ZERO, 0)
	var ordinary: PieceState = run.state.rules.place_piece(Vector2i(1, 1), 1)
	assert_false(run.execute_command(_command(run, ordinary)).accepted)
	assert_eq(ManualActivationRules.remaining(run.state, true), 3)
	var config: ExplosionConfig = run.abilities.config.duplicate() as ExplosionConfig
	config.event_budget = 1
	run.abilities.config = config
	assert_false(run.execute_command(_command(run, source)).accepted)
	assert_eq(ManualActivationRules.remaining(run.state, true), 3)
	run.abilities.config = AbilityResolver.DEFAULT_CONFIG
	var stale: RunCommand = _command(run, source)
	stale.expected_action_id = 999
	assert_false(run.execute_command(stale).accepted)
	assert_eq(ManualActivationRules.remaining(run.state, true), 3)
	assert_true(run.execute_command(_command(run, source)).accepted)
	assert_eq(ManualActivationRules.remaining(run.state, true), 2)
	assert_eq(run.state.ledger.total, 0)

func test_cross_chain_charges_root_only_and_shared_config_is_not_mutated() -> void:
	var run: RunController = _run("fixture_line_cross")
	var config: String = RunSnapshot.digest(RunSnapshot.config(run))
	var source: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(Vector2i(2, 4)))
	var outcome: CommandResult = run.execute_command(_command(run, source))
	assert_true(outcome.accepted)
	assert_eq(outcome.turn.matches.size(), 4)
	assert_eq(run.state.manual_uses_used, {ManualActivationRules.LINE.skill_id: 1})
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config)
	var other: RunController = _run("fixture_line_cross")
	assert_eq(ManualActivationRules.remaining(other.state, true), 3)
	run.state.reset_counters()
	assert_true(run.state.manual_uses_used.is_empty())
	assert_eq(ManualActivationRules.LINE.manual_use_limit, 3)

func test_exhaustion_file_replay_and_telemetry_preserve_uses_and_rejected_attempt() -> void:
	var run: RunController = _run("fixture_manual_limit")
	var projector: TelemetryProjector = TelemetryProjector.new(MemorySink.new(), "manual-limit-test")
	run.recorder = RunRecorder.new()
	run.recorder.record_appended.connect(projector.observe_record)
	run.recorder.begin(run, "fixture", true)
	for position: Vector2i in [Vector2i(0, 0), Vector2i(0, 2), Vector2i(4, 4), Vector2i(0, 6)]:
		var source: PieceState = run.state.rules.state.get_piece(run.state.rules.state.get_piece_id(position))
		var outcome: CommandResult = run.execute_command(_command(run, source))
		if position == Vector2i(0, 6): assert_eq(outcome.reason, "manual_uses_exhausted")
		else:
			assert_true(outcome.accepted)
			_finish(run)
	run.recorder.finish(run, "abandoned", "manual_limit_test")
	assert_eq(run.recorder.error, "")
	assert_eq(projector.error, "")
	var actions: int = 0
	var rejected: int = 0
	for event: Dictionary in projector.events:
		if event.event_name == "action_resolved": actions += 1
		if event.event_name == "command_resolved" and not event.payload.accepted:
			rejected += 1
			assert_eq(event.payload.manual_uses_before, event.payload.manual_uses_after)
			assert_eq(event.payload.manual_uses_after.line_manual_clear, "3")
	assert_eq(actions, 3)
	assert_eq(rejected, 1)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), RunSnapshot.digest(RunSnapshot.capture(replay.run)))
