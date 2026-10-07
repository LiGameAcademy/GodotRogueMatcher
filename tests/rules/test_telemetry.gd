extends GutTest

const JSON_CODEC: Script = preload("res://addons/godot_core_system/source/utils/io_strategies/serialization/json_serialization_strategy.gd")

class MemorySink extends TelemetrySink:
	var events: Array[Dictionary] = []
	var fail: bool = false
	func append_event(event: Dictionary) -> TelemetryWriteResult:
		events.append(event.duplicate(true))
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.FAILED, "test_write_failure") if fail else TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)
	func close() -> TelemetryWriteResult:
		return flush()

class FakeClock extends RefCounted:
	var now_ms: int = 0
	func now() -> int:
		return now_ms

var run: RunController
var projector: TelemetryProjector

func _start(source: String = "human", seed_value: int = 1000, destination: TelemetrySink = null, timer: Callable = Callable(), fixture: bool = false) -> void:
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialize("fixture_f6" if fixture else "normal")
	run.recorder = RunRecorder.new()
	projector = TelemetryProjector.new(destination if destination != null else MemorySink.new(), "session-test", timer)
	run.recorder.record_appended.connect(projector.observe_record)
	run.recorder.begin(run, source, false)

func _offer() -> SkillOffer:
	var bot: GreedyBot = GreedyBot.new(101000)
	for step: int in range(300):
		if run.state.rewards.active_offer != null: return run.state.rewards.active_offer
		if run.state.phase == RunState.Phase.INPUT: run.execute_command(bot.choose(run))
		else: run.advance()
	fail_test("expected_offer_not_reached")
	return null

func _events(name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in projector.events:
		if event.event_name == name: result.append(event)
	return result

func test_collecting_and_failed_sink_do_not_change_rules_or_random_streams() -> void:
	var strategy: GreedyBot = GreedyBot.new()
	strategy.config = strategy.config.duplicate(true) as BotConfig
	strategy.config.move_limit = 30
	var plain: RunRecorder = BotRunner.new().play(1000, 101000, strategy, false)
	for fail: bool in [false, true]:
		var runner: BotRunner = BotRunner.new()
		runner.telemetry_factory = TelemetryFactory.new("test-session")
		runner.telemetry_factory.sink_factory = func(_id: String) -> TelemetrySink:
			var destination: MemorySink = MemorySink.new()
			destination.fail = fail
			return destination
		var collected: RunRecorder = runner.play(1000, 101000, strategy, false)
		assert_eq(RunSnapshot.digest(plain.records.back().final), RunSnapshot.digest(collected.records.back().final))
		assert_eq(runner.last_replay_error, "")
		assert_eq(runner.last_telemetry.error.is_empty(), not fail)
		assert_eq(runner.last_telemetry.events.back().payload.record_complete, not fail)

func test_generated_without_visible_popup_is_not_human_exposure() -> void:
	_start()
	assert_not_null(_offer())
	run.recorder.finish(run, "abandoned", "not_presented")
	var report: TelemetryReport = TelemetryReport.new()
	report.add(projector.events)
	var opportunities: Dictionary = report.summary().opportunities
	assert_eq(opportunities.human_generated_not_presented, 1)
	for row: Dictionary in opportunities.skills.values():
		assert_eq(row.opportunities, 0)
		assert_null(row.conditional_selection_rate)

func test_repeated_presentation_failed_choice_and_duplicate_confirmation_are_deduplicated() -> void:
	_start()
	var offer: SkillOffer = _offer()
	var order: Array[String] = []
	for skill: SkillDefinition in offer.choices: order.append(String(skill.skill_id))
	assert_true(projector.offer_presented(offer.offer_id, order))
	assert_true(projector.offer_presented(offer.offer_id, order))
	var choice: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	choice.offer_id = offer.offer_id
	choice.reward_id = offer.reward_id
	choice.skill_id = &"invalid_skill"
	assert_false(run.execute_command(choice).accepted)
	choice = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	choice.offer_id = offer.offer_id
	choice.reward_id = offer.reward_id
	choice.skill_id = offer.choices[0].skill_id
	var applied: CommandResult = run.execute_command(choice)
	assert_true(applied.accepted)
	assert_same(run.execute_command(choice), applied)
	assert_eq(_events("skill_acquired").size(), 1)
	run.recorder.finish(run, "abandoned", "test_complete")
	var report: TelemetryReport = TelemetryReport.new()
	report.add(projector.events)
	report.add(projector.events)
	assert_eq(report.runs.size(), 1)
	var opportunities: Dictionary = report.summary().opportunities
	assert_eq(opportunities.failed_choices, 1)
	for row: Dictionary in opportunities.skills.values(): assert_eq(row.opportunities, 1)

func test_bot_opportunities_use_generated_offers_without_fake_presentations() -> void:
	_start("bot")
	var offer: SkillOffer = _offer()
	assert_false(projector.offer_presented(offer.offer_id, ["core_drop"]))
	run.recorder.finish(run, "censored", "test_limit")
	var report: TelemetryReport = TelemetryReport.new()
	report.add(projector.events)
	for row: Dictionary in report.summary().opportunities.skills.values(): assert_eq(row.opportunities, 1)
	assert_eq(_events("offer_presented").size(), 0)

func test_clock_priority_focus_and_closing_total_are_exclusive() -> void:
	var timer: FakeClock = FakeClock.new()
	_start("human", 7, null, timer.now)
	var observation: BoardObservation = BoardObservation.new()
	observation.attach(projector)
	timer.now_ms = 10
	observation.busy(false)
	timer.now_ms = 30
	observation.present_offer(SkillOffer.new())
	timer.now_ms = 50
	observation.paused(true)
	timer.now_ms = 70
	observation.focused(false)
	timer.now_ms = 120
	observation.focused(true)
	timer.now_ms = 150
	observation.paused(false)
	timer.now_ms = 170
	observation.selecting_skill()
	timer.now_ms = 200
	run.recorder.finish(run, "abandoned", "time_test")
	var ending: Dictionary = _events("run_ended")[0].payload
	assert_eq(ending.observed_ms, "200")
	assert_eq(ending.active_ms, "150")
	assert_eq(ending.times.inactive, "50")
	var duration: int = 0
	for interval: Dictionary in _events("observation_interval_closed"): duration += interval.payload.duration_ms.to_int()
	assert_eq(duration, 200)

func test_inputs_have_one_terminal_disposition_and_command_link() -> void:
	_start()
	var first: String = projector.begin_input("move", true)
	projector.resolve_input(first, "overwritten", "new_target")
	projector.resolve_input(first, "submitted", "duplicate", "1")
	var second: String = projector.begin_input("move", true)
	projector.resolve_input(second, "submitted", "", "9007199254740993", 14)
	projector.begin_input("move", true)
	run.recorder.finish(run, "abandoned", "restart")
	var inputs: Array[Dictionary] = _events("input_resolved")
	assert_eq(inputs.size(), 3)
	assert_eq(inputs[0].payload.disposition, "overwritten")
	assert_eq(inputs[1].command_id, "9007199254740993")
	assert_eq(inputs[1].payload.buffer_wait_ms, "14")
	assert_eq(inputs[2].payload.disposition, "discarded")

func test_turn_aggregates_chain_and_generated_entities_once() -> void:
	_start("fixture", 7, null, Callable(), true)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	assert_true(run.execute_command(command).accepted)
	while run.state.phase != RunState.Phase.INPUT: run.advance()
	run.recorder.finish(run, "abandoned", "chain_test")
	var turns: Array[Dictionary] = _events("turn_resolved")
	assert_eq(turns.size(), 1)
	assert_true(turns[0].payload.space_consistent)
	assert_true(turns[0].payload.complete)
	var score: int = 0
	for entry: Dictionary in turns[0].payload.ledger_entries: score += entry.final_score.to_int()
	assert_eq(score, 70)
	assert_eq(turns[0].payload.score_after, "70")
	assert_eq(_events("run_ended")[0].payload.moves, "1")

func test_local_sink_readback_precision_truncation_and_schema_rejection() -> void:
	var destination: LocalJsonlSink = LocalJsonlSink.new("telemetry-test-" + str(Time.get_ticks_usec()), "user://telemetry_tests")
	_start("human", 9223372036854775807, destination)
	run.recorder.finish(run, "abandoned", "file_test")
	var reader: TelemetryReader = TelemetryReader.new()
	var read: Array[Dictionary] = reader.read_file(destination.path)
	assert_eq(reader.error, "")
	assert_true(reader.complete)
	assert_eq(read.size(), projector.events.size())
	assert_eq(read[0].event_id, projector.events[0].event_id)
	var changed: Dictionary = read[0].duplicate(true)
	changed.schema_version = "99"
	assert_eq(TelemetrySchema.validate(changed), "unsupported_telemetry_schema")
	changed = read[0].duplicate(true)
	changed.payload.ordinary = "01"
	assert_eq(TelemetrySchema.validate(changed), "invalid_integer_ordinary")
	var file: FileAccess = FileAccess.open(destination.path + ".truncated", FileAccess.WRITE)
	file.store_line(RunSnapshot.canonical(read[0]))
	file.store_string("{\"broken\"")
	file.close()
	assert_eq(reader.read_file(destination.path + ".truncated").size(), 1)
	assert_false(reader.complete)
	assert_eq(reader.error, "incomplete_last_line")
	assert_eq(LocalJsonlSink.new("../bad").error, "invalid_run_id")

func test_core_json_strategy_works_without_autoload_and_preserves_null_error_boundary() -> void:
	var codec: RefCounted = JSON_CODEC.new()
	codec.set("indent", "")
	var bytes: PackedByteArray = codec.call("serialize", {"id": "9223372036854775807"})
	var decoded: Dictionary = codec.call("deserialize", bytes)
	assert_eq(decoded.id, "9223372036854775807")
	assert_eq(codec.get("last_error"), "")
	assert_null(codec.call("deserialize", "null".to_utf8_buffer()))
	assert_eq(codec.get("last_error"), "")
	assert_null(codec.call("deserialize", "{broken".to_utf8_buffer()))
	assert_false(String(codec.get("last_error")).is_empty())
	assert_null(codec.call("deserialize", "".to_utf8_buffer()))
	assert_eq(codec.get("last_error"), "")

func test_overlapping_prefix_and_complete_files_count_one_run() -> void:
	_start()
	run.recorder.finish(run, "abandoned", "merge_test")
	var prefix: Array[Dictionary] = []
	prefix.assign(projector.events.slice(0, projector.events.size() - 1))
	var report: TelemetryReport = TelemetryReport.new()
	report.add(prefix, "missing_ending")
	report.add(projector.events)
	report.add(prefix, "missing_ending")
	assert_eq(report.runs.size(), 1)
	assert_true(report.runs[0].record_complete)
	assert_eq(report.events.size(), projector.events.size())
	assert_eq(report.runs[0].moves, "0")
	assert_true(report.write("user://telemetry_tests/overlap_report"))
	assert_true(FileAccess.file_exists("user://telemetry_tests/overlap_report/events.csv"))

func test_experiment_variant_and_bot_configuration_are_separate_groups() -> void:
	_start("bot")
	assert_not_null(_offer())
	run.recorder.finish(run, "censored", "group_test")
	var report: TelemetryReport = TelemetryReport.new()
	for index: int in range(3):
		var copy: Array[Dictionary] = []
		for original: Dictionary in projector.events:
			var event: Dictionary = original.duplicate(true)
			event.run_id = "group-run-" + str(index)
			event.event_id = event.run_id + ":" + event.telemetry_seq
			event.experiment_id = "board-capacity"
			event.variant_id = "A" if index < 2 else "B"
			event.bot_config_hash = "config-1" if index != 1 else "config-2"
			copy.append(event)
		report.add(copy)
	assert_eq(report.summary().groups.size(), 3)
	for row: Dictionary in report.summary().opportunities.skills.values(): assert_eq(row.opportunities, 1)
	var conflicting: Array[Dictionary] = []
	conflicting.assign(projector.events.duplicate(true))
	conflicting[0].run_id = "group-run-0"
	conflicting[0].event_id = "group-run-0:1"
	report.add(conflicting)
	assert_eq(report.runs.size(), 3)
	assert_eq(report.errors.back().reason, "conflicting_run_metadata")

func test_active_core_turn_counts_source_removal_and_reports_action() -> void:
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 77)
	run.initialize("fixture_demolition")
	run.recorder = RunRecorder.new()
	projector = TelemetryProjector.new(MemorySink.new(), "session-active")
	run.recorder.record_appended.connect(projector.observe_record)
	run.recorder.begin(run, "fixture", false)
	var command: RunCommand = GreedyBot.new().choose(run)
	assert_true(command is DetonateCoreCommand)
	assert_true(run.execute_command(command).accepted)
	for stage: int in range(6):
		if run.advance().kind == &"input": break
	run.recorder.finish(run, "abandoned", "fixture_complete")
	assert_eq(projector.error, "")
	var turns: Array[Dictionary] = _events("turn_resolved")
	assert_eq(turns.size(), 1)
	assert_true(turns[0].payload.space_consistent)
	assert_eq(turns[0].payload.removed_companions, "1")
	assert_eq(_events("run_ended")[0].payload.actions, "1")
	var report: RunAnalysis = RunAnalysis.new()
	report.add(run.recorder.records)
	assert_eq(report.turns.size(), 1)
	assert_eq(report.turns[0].command_type, "detonate")
	assert_eq(report.runs[0].activations, "1")
