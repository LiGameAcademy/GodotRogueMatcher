extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_normal_scene_records_submitted_command_and_turn_without_false_exposure() -> void:
	var command: MovePieceCommand = RandomLegalBot.new(9).choose(board.run) as MovePieceCommand
	var telemetry: TelemetryProjector = board.observation.telemetry
	board.selected_piece = board.view.get_piece(command.piece_id)
	assert_true(await board.move_selected_piece(board.get_cell(command.target), 0.01))
	assert_eq(telemetry.error, "")
	var submitted: Dictionary = _events(telemetry, "input_resolved").back()
	assert_eq(submitted.payload.disposition, "submitted")
	assert_eq(submitted.command_id, "1")
	assert_eq(_events(telemetry, "action_resolved").size(), 1)
	assert_eq(_events(telemetry, "offer_presented").size(), 0)
	board.run.recorder.finish(board.run, "abandoned", "scene_sample")
	var reader: TelemetryReader = TelemetryReader.new()
	var sink: LocalJsonlSink = telemetry.sink as LocalJsonlSink
	assert_gt(reader.read_file(sink.path).size(), 3)
	assert_eq(reader.error, "")
	assert_true(reader.complete)

func test_real_popup_produces_visible_exposure_then_acquisition_once() -> void:
	# F7先结束正常采样；这条UI专项显式从fixture记录继续，避免计入正常数值。
	assert_true(board.load_explosion_demo())
	var telemetry: TelemetryProjector = board.observation.telemetry
	GameManager.add_score(100)
	LevelUpSystem.resolve_pending_rewards(board)
	await (main.get_node("Game/UILayer/HUD") as Hud).wait_for_score()
	await wait_process_frames(4)
	assert_true(UIManager.current_popup is PopupSkillChoice)
	assert_eq(_events(telemetry, "offer_generated").size(), 1)
	assert_eq(_events(telemetry, "offer_presented").size(), 1)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	popup._select(0)
	await wait_process_frames(4)
	assert_eq(_events(telemetry, "skill_acquired").size(), 1)
	assert_eq(_events(telemetry, "input_resolved").back().payload.type, "choose_skill")
	assert_eq(telemetry.error, "")

func test_buffer_overwrite_and_reward_cancel_are_terminal_events() -> void:
	var telemetry: TelemetryProjector = board.observation.telemetry
	var first: PieceState = board.rules.state.get_snapshot()[0]
	var second: PieceState = board.rules.state.get_snapshot()[1]
	board._buffer_input(first.coordinate)
	board._buffer_input(second.coordinate)
	board.cancel_buffered_input("reward_popup")
	var events: Array[Dictionary] = _events(telemetry, "input_resolved")
	assert_eq(events.size(), 2)
	assert_eq(events[0].payload.disposition, "overwritten")
	assert_eq(events[1].payload.disposition, "cancelled")
	assert_eq(events[1].payload.reason, "reward_popup")

func test_retry_closes_old_sink_and_keeps_session_but_changes_run_id() -> void:
	var old: TelemetryProjector = board.observation.telemetry
	var old_session: String = old.events[0].session_id
	var old_run: String = old.events[0].run_id
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	assert_true(old.ended)
	assert_eq(_events(old, "run_ended").size(), 1)
	assert_eq(board.observation.telemetry.events[0].session_id, old_session)
	assert_ne(board.observation.telemetry.events[0].run_id, old_run)
	assert_eq(board.observation.telemetry.error, "")

func _events(telemetry: TelemetryProjector, name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in telemetry.events:
		if event.event_name == name: result.append(event)
	return result

func test_mode_switch_records_own_reason_and_integration_context() -> void:
	var game: Node2D = main.get_node("Game") as Node2D
	var old: TelemetryProjector = board.observation.telemetry
	var before: StringName = board.run.state.mode_id()
	game._select_mode(&"classic_endless" if before == &"stage_challenge" else &"stage_challenge")
	await game._on_retry_requested()
	assert_true(old.ended)
	assert_eq(_events(old, "run_ended")[0].payload.reason, "mode_switch")
	assert_eq(old.events[0].collection_context, "automated_integration")
	assert_ne(board.observation.telemetry.events[0].run_id, old.events[0].run_id)
	assert_ne(board.run.state.mode_id(), before)

func test_help_export_controls_preserve_rules_and_normalize_ui_exit_location() -> void:
	var game: Node2D = main.get_node("Game") as Node2D
	var collection: RunCollection = game.get_node("RunCollection") as RunCollection
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	game.set("_has_played", true)
	game._show_menu()
	assert_true(get_tree().paused)
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	assert_false(menu.collection_controls.export_button.disabled)
	menu.collection_controls.export_requested.emit()
	assert_false(collection.last_export.is_empty())
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)
	collection.close("window_close_requested")
	var summary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(board.observation.telemetry.summary_path))
	assert_eq(summary.exit_observation.ui, "help")
	assert_eq(summary.reason, "window_close_requested")
