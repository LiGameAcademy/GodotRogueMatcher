extends GutTest

## Real rule-generated opportunities; synthetic source labels exercise observation semantics only.
const EXPLANATIONS: Script = preload("res://services/telemetry/offer_explanation_schema.gd")
var _run: RunController
var _projector: TelemetryProjector

class MemorySink extends TelemetrySink:
	func append_event(_event: Dictionary) -> TelemetryWriteResult:
		return TelemetryWriteResult.new()
	func flush() -> TelemetryWriteResult:
		return TelemetryWriteResult.new(TelemetryWriteResult.Status.PERSISTED)
	func close() -> TelemetryWriteResult:
		return flush()

func _fixture(source: String = "bot", seed_value: int = 86) -> void:
	var stage: StageConfig = StageConfig.new()
	stage.targets = [1, 10000]
	stage.pressure_intervals = [4, 4]
	_run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value, stage)
	_run.initialize("fixture_f6")
	_run.recorder = RunRecorder.new()
	_run.recorder.metadata = {"synthetic": true, "purpose": "offer measurement regression; no human observation"}
	_projector = TelemetryProjector.new(MemorySink.new(), "measurement-test")
	_run.recorder.record_appended.connect(_projector.observe_record)
	_run.recorder.begin(_run, source, false)
	var command: MovePieceCommand = MovePieceCommand.new(_run.state.run_id, 1, 0)
	command.piece_id = _run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	assert_true(_run.execute_command(command).accepted)
	for step: int in range(20):
		if _run.state.rewards.active_offer != null: break
		_run.advance()
	assert_not_null(_run.state.rewards.active_offer)

func _generated() -> Dictionary:
	for event: Dictionary in _projector.events:
		if event.event_name == "offer_generated": return event
	return {}

func test_real_offer_explanation_schema_csv_and_command_replay_are_consistent() -> void:
	_fixture()
	var event: Dictionary = _generated()
	assert_eq(event.payload.explanations.size(), 52)
	assert_eq(EXPLANATIONS.validate(event.payload), "")
	for row: Dictionary in _projector.events: assert_eq(TelemetrySchema.validate(row), "")
	var command: RunCommand = RandomLegalBot.new(99).choose(_run)
	assert_true(_run.execute_command(command).accepted)
	for step: int in range(20):
		if _run.state.phase == RunState.Phase.INPUT: break
		_run.advance()
	_run.recorder.finish(_run, "censored", "measurement_probe")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(_run.recorder.records), replay.error)
	var report: TelemetryReport = TelemetryReport.new()
	report.add(_projector.events)
	report.add(_projector.events)
	var summary: Dictionary = report.summary().opportunities
	assert_eq(summary.eligibility.size(), 52)
	for row: Dictionary in summary.eligibility.values(): assert_eq(row.observed_rewards, 1)
	for row: Dictionary in summary.skills.values():
		assert_eq(row.opportunities, 1)
		assert_eq(row.legal_pool_rewards, 1)
		assert_eq(row.eligibility_rate, 1.0)
	var directory: String = "user://offer_measurements/%s" % str(Time.get_ticks_usec())
	assert_true(report.write(directory), report.error)
	assert_string_contains(FileAccess.get_file_as_string(directory.path_join("offers.csv")), "explanations")
	assert_string_contains(FileAccess.get_file_as_string(directory.path_join("offers.csv")), "denominator")

func test_corrupt_binary_factors_weights_or_denominators_are_explicit_schema_errors() -> void:
	_fixture()
	var original: Dictionary = _generated().payload
	var id: String = original.choices[0]
	for invalid: int in range(12):
		var data: Dictionary = original.duplicate(true)
		if invalid == 0: data.explanations[id].H = "2"
		if invalid == 1: data.explanations[id].Q = 0.0
		if invalid == 2: data.explanations[id].W += 1.0
		if invalid == 3: data.slots[0].denominator += 1.0
		if invalid == 4: data.slots[0].selected = 1
		if invalid == 5: data.erase("explanations")
		if invalid == 6: data.explanations[id].factor_before_clamp += 1.0
		if invalid == 7: data.choices[0] = "not_in_catalog"
		if invalid == 8: data.choices[1] = data.choices[0]
		if invalid == 9: data.weights[id] += 1.0
		if invalid == 10: data.weights.erase(id)
		if invalid == 11: data.choices.clear()
		assert_false(EXPLANATIONS.validate(data).is_empty(), str(invalid))

func test_synthetic_replacement_trace_counts_one_reward_and_does_not_call_it_a_refusal() -> void:
	_fixture()
	var events: Array[Dictionary] = []
	for event: Dictionary in _projector.events:
		events.append(event.duplicate(true))
		if event.event_name != "offer_generated": continue
		var replaced: Dictionary = event.duplicate(true)
		replaced.telemetry_seq = str(events.size() + 1)
		replaced.event_id = event.run_id + ":" + replaced.telemetry_seq
		replaced.payload.replaces_offer_id = event.payload.offer_id
		replaced.payload.offer_id = "999"
		replaced.offer_id = "999"
		assert_eq(TelemetrySchema.validate(replaced), "")
		events.append(replaced)
	var report: TelemetryReport = TelemetryReport.new()
	report.add(events)
	var summary: Dictionary = report.summary().opportunities
	assert_eq(summary.replaced_groups, 1)
	assert_eq(summary.failed_choices, 0)
	for row: Dictionary in summary.skills.values():
		assert_eq(row.generated, 1)
		assert_eq(row.opportunities, 1)
	for row: Dictionary in summary.eligibility.values(): assert_eq(row.observed_rewards, 1)

func test_legacy_missing_explanations_stay_unknown_and_hidden_human_offers_are_not_exposures() -> void:
	_fixture("human")
	var events: Array[Dictionary] = _projector.events.duplicate(true)
	for event: Dictionary in events:
		if event.event_name != "offer_generated": continue
		event.payload.explanations = {}
		event.payload.slots = []
		event.payload.offer_rules_version = "legacy-fixture"
	var report: TelemetryReport = TelemetryReport.new()
	report.add(events)
	var summary: Dictionary = report.summary().opportunities
	assert_true(summary.eligibility.is_empty())
	assert_eq(summary.human_generated_not_presented, 1)
	assert_eq(summary.legacy_groups_without_explanations, 1)
	for row: Dictionary in summary.skills.values():
		assert_eq(row.opportunities, 0)
		assert_null(row.conditional_selection_rate)
		assert_null(row.legal_pool_rewards)
		assert_null(row.eligibility_rate)
