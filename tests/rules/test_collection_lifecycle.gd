extends GutTest

var collection: RunCollection
var run: RunController

func before_each() -> void:
	collection = load("res://services/telemetry/run_collection.tscn").instantiate() as RunCollection
	add_child_autofree(collection)
	var factory: TelemetryFactory = TelemetryFactory.new()
	factory.directory = "user://collection_lifecycle/" + factory.session_id
	collection.configure("automated_integration", factory)
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "fixture", false)
	collection.bind(run)

func _move() -> void:
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	assert_true(run.execute_command(command).accepted)

func _drain() -> void:
	for step: int in range(30):
		if run.state.phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS, RunState.Phase.FINISHED]: return
		run.advance()

func test_exit_during_action_records_incomplete_root_and_unique_summary() -> void:
	_move()
	collection.location("presentation")
	collection.finish("window_close_requested")
	var projector: TelemetryProjector = collection.factory.projectors[0]
	var summary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(projector.summary_path))
	assert_eq(summary.reason, "window_close_requested")
	assert_eq(summary.complete_actions, "0")
	assert_eq(summary.exit_observation.ui, "presentation")
	assert_false(summary.exit_observation.root_complete)
	assert_true(summary.record_complete)
	var before: String = FileAccess.get_file_as_string(projector.summary_path)
	collection.finish("scene_closed")
	assert_eq(FileAccess.get_file_as_string(projector.summary_path), before)
	var actions: Array[Dictionary] = _events(projector, "action_resolved")
	assert_eq(actions.size(), 1)
	assert_false(actions[0].payload.complete)

func test_finished_action_conserves_score_and_space_and_recovers_only_prefix() -> void:
	_move()
	_drain()
	collection.flush()
	var projector: TelemetryProjector = collection.factory.projectors[0]
	var sink: LocalJsonlSink = projector.sink as LocalJsonlSink
	var actions: Array[Dictionary] = _events(projector, "action_resolved")
	assert_eq(actions.size(), 1)
	assert_true(actions[0].payload.complete)
	assert_true(actions[0].payload.space_consistent)
	var score: int = 0
	for entry: Dictionary in actions[0].payload.ledger_entries: score += int(entry.final_score)
	assert_eq(score, int(actions[0].payload.action_score_delta))
	var prefix: String = FileAccess.get_file_as_string(sink.path)
	var recovered: Dictionary = TelemetrySummary.recover(sink.path)
	assert_eq(recovered.end_class, "unexpected_stop")
	assert_eq(recovered.reason, "unknown")
	assert_false(recovered.record_complete)
	assert_eq(recovered.complete_actions, "1")
	assert_eq(recovered.last_complete_action_id, "1")
	assert_true(recovered.last_observation.root_complete)
	assert_not_null(recovered.last_observed_utc)
	assert_eq(FileAccess.get_file_as_string(sink.path), prefix)
	collection.finish("quit_button")
	assert_eq(TelemetrySummary.recover(sink.path).end_class, "user_stop")

func test_live_session_is_never_recovered_and_zip_contains_current_prefix() -> void:
	_move()
	_drain()
	collection.flush()
	var next: TelemetryFactory = TelemetryFactory.new()
	next.directory = collection.factory.directory
	var observer: CollectionSession = CollectionSession.new()
	observer.start(next)
	assert_true(observer.recovered.is_empty())
	observer.close("test_done")
	var archive: String = collection.export_files()
	assert_false(archive.is_empty())
	var zip: ZIPReader = ZIPReader.new()
	assert_eq(zip.open(archive), OK)
	assert_true(zip.get_files().has("telemetry/" + run.state.run_id + ".jsonl"))
	assert_false(zip.get_files().has(archive.get_file()))
	zip.close()

func test_end_screen_session_location_does_not_rewrite_gameplay_ending() -> void:
	run.finish_game(&"board_full")
	collection.finish("window_close_requested")
	var projector: TelemetryProjector = collection.factory.projectors[0]
	var before: String = FileAccess.get_file_as_string(projector.summary_path)
	collection.location("result")
	collection.close("quit_button")
	var summary: Dictionary = JSON.parse_string(before)
	assert_eq(summary.reason, "board_full")
	assert_eq(summary.end_class, "gameplay_terminal")
	assert_eq(FileAccess.get_file_as_string(projector.summary_path), before)
	assert_true(FileAccess.get_file_as_string(collection.session.path).contains("result"))

func test_failed_directory_does_not_reject_legal_command() -> void:
	var factory: TelemetryFactory = TelemetryFactory.new()
	factory.directory = collection.factory.directory.path_join("failed")
	var recorder: RunRecorder = RunRecorder.new()
	var projector: TelemetryProjector = factory.attach(recorder, "failure-" + str(Time.get_ticks_usec()))
	(projector.sink as LocalJsonlSink).maximum_bytes = 1
	recorder.begin(run, "fixture", false)
	assert_false(projector.error.is_empty())
	_move()
	_drain()
	assert_eq(run.state.valid_moves, 1)
	assert_eq(run.state.rule_error, "")
	recorder.finish(run, "abandoned", "test")

func _events(projector: TelemetryProjector, name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in projector.events:
		if event.event_name == name: result.append(event)
	return result

func test_goal_reward_score_stays_outside_completed_action_and_has_own_identity() -> void:
	collection.finish("fixture_restart")
	var config: StageConfig = StageConfig.new()
	config.targets = [100, 1000]
	config.pressure_intervals = [4, 4]
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	run.initialize("fixture_dye")
	for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), 1)
	run.recorder = RunRecorder.new()
	var projector: TelemetryProjector = collection.factory.attach(run.recorder, run.state.run_id)
	run.recorder.begin(run, "fixture", false)
	collection.bind(run)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(4, 6))
	command.target = Vector2i(4, 4)
	assert_true(run.execute_command(command).accepted)
	_drain()
	var action: Dictionary = _events(projector, "action_resolved")[0]
	assert_true(action.payload.complete)
	assert_eq(action.payload.action_score_delta, "105")
	assert_eq(_events(projector, "stage_goal_completed").size(), 1)
	var goal: Dictionary = _events(projector, "stage_goal_completed")[0]
	assert_true(goal.payload.goal_effects_implemented)
	assert_eq(goal.payload.implemented_goal_effects, ["goal_score_bonus"])
	assert_eq(goal.payload.P_before, goal.payload.P_after)
	var skill: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
	var target: SkillTarget = SkillTarget.new()
	target.coordinate = Vector2i(4, 0)
	target.color = 1
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = target
	run.state.rewards.active_offer = offer
	run.recorder.offer(run, offer)
	var choice: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 2, run.state.action_id)
	choice.offer_id = offer.offer_id
	choice.reward_id = offer.reward_id
	choice.skill_id = skill.skill_id
	assert_true(run.execute_command(choice).accepted)
	assert_eq(run.state.ledger.total, 155)
	assert_eq(_events(projector, "action_resolved").size(), 1)
	var acquired: Dictionary = _events(projector, "skill_acquired")[0]
	assert_eq(acquired.payload.score_delta, "50")
	assert_null(acquired.root_action_id)
	assert_eq(acquired.batch_id, "reward:1")
	assert_eq(_events(projector, "offer_generated")[0].payload.stage.q, "3")
	collection.finish("test_complete")
