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

func test_truncated_pool_omitted_candidate_and_forged_quota_are_rejected() -> void:
	_fixture()
	var original: Dictionary = _generated().payload
	assert_eq(EXPLANATIONS.validate(original), "")
	var truncated: Dictionary = original.duplicate(true)
	truncated.slots.resize(1)
	truncated.generation_order.resize(1)
	truncated.choices = truncated.generation_order.duplicate()
	assert_false(EXPLANATIONS.validate(truncated).is_empty(), "legal remaining candidates require more slots")
	var omitted: Dictionary = original.duplicate(true)
	var slot: Dictionary = omitted.slots[0]
	for id: String in slot.weights.keys():
		if id != slot.selected:
			slot.weights.erase(id)
			break
	var ids: Array = slot.weights.keys()
	ids.sort()
	var before: float = 0.0
	slot.denominator = 0.0
	for id: String in ids:
		if id == slot.selected: before = slot.denominator
		slot.denominator += slot.weights[id]
	slot.sample = (before + slot.weights[slot.selected] * 0.5) / slot.denominator
	assert_false(EXPLANATIONS.validate(omitted).is_empty(), "self-consistent subset is not the legal pool")
	for invalid: int in range(5):
		var data: Dictionary = original.duplicate(true)
		if invalid == 0: data.slots[0].quota_excluded.append(data.slots[0].selected)
		if invalid == 1: data.slots[0].slot = "9"
		if invalid == 2: data.slots.append(data.slots.back().duplicate(true))
		if invalid == 3: data.explanations[data.choices[0]].weight_before_clamp += 1.0
		if invalid == 4: data.explanations[data.choices[0]].erase("utility_pick")
		assert_false(EXPLANATIONS.validate(data).is_empty(), str(invalid))

func test_legacy_acquisition_without_reward_id_joins_its_generated_offer() -> void:
	_fixture("human")
	var offer: Dictionary = _generated()
	var display_order: Array[String] = []
	display_order.assign(offer.payload.choices)
	assert_true(_projector.offer_presented(offer.payload.offer_id.to_int(), display_order))
	var command: RunCommand = RandomLegalBot.new(99).choose(_run)
	assert_true(_run.execute_command(command).accepted)
	var events: Array[Dictionary] = _projector.events.duplicate(true)
	for event: Dictionary in events:
		if event.event_name != "skill_acquired": continue
		event.payload.erase("reward_id")
		event.reward_id = null
		assert_eq(TelemetrySchema.validate(event), "")
	var report: TelemetryReport = TelemetryReport.new()
	report.add(events)
	var summary: Dictionary = report.summary().opportunities
	var acquired_count: int = 0
	for row: Dictionary in summary.skills.values(): acquired_count += row.acquired
	assert_eq(acquired_count, 1)
	assert_eq(summary.presented_not_consumed, 0)
	# A restored observation of the same parent reward must not double exposure or success.
	var restored: Array[Dictionary] = events.duplicate(true)
	for event: Dictionary in restored:
		event.parent_run_id = event.run_id
		event.run_id = "restored-observation"
		event.event_id = event.run_id + ":" + event.telemetry_seq
		assert_eq(TelemetrySchema.validate(event), "")
	report.add(restored)
	summary = report.summary().opportunities
	acquired_count = 0
	for row: Dictionary in summary.skills.values():
		acquired_count += row.acquired
		assert_eq(row.opportunities, 1)
	assert_eq(acquired_count, 1)
	assert_eq(summary.presented_not_consumed, 0)

func test_v1_telemetry_is_legacy_coverage_and_v45_replay_is_explicitly_rejected() -> void:
	_fixture()
	var events: Array[Dictionary] = _projector.events.duplicate(true)
	for event: Dictionary in events:
		if event.event_name != "offer_generated": continue
		event.payload.offer_rules_version = "offer-unified-trial-v1"
		for row: Dictionary in event.payload.explanations.values(): row.erase("utility_pick")
		assert_eq(TelemetrySchema.validate(event), "")
	var legacy: TelemetryReport = TelemetryReport.new()
	legacy.add(events)
	assert_eq(legacy.summary().opportunities.pool_audit, {"complete_rewards": 0, "legacy_rewards": 1, "complete_rate": 0.0})
	var current: TelemetryReport = TelemetryReport.new()
	current.add(_projector.events)
	assert_eq(current.summary().opportunities.pool_audit, {"complete_rewards": 1, "legacy_rewards": 0, "complete_rate": 1.0})
	_run.recorder.finish(_run, "censored", "audit_probe")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay(_run.recorder.records), replay.error)
	var altered: Array[Dictionary] = _run.recorder.records.duplicate(true)
	for record: Dictionary in altered:
		if record.kind != "Offer": continue
		var id: String = record.offer.choices[0]
		record.offer.explanations[id].utility_pick = not record.offer.explanations[id].utility_pick
	assert_false(replay.replay(altered))
	assert_string_contains(replay.error, "explanations")
	altered = _run.recorder.records.duplicate(true)
	altered[0].rules_version = "run-commands-v45-unified-offers"
	assert_false(replay.replay(altered))
	assert_eq(replay.error, "record_version_mismatch")
