extends GutTest
## Automated GUI routing evidence for #192; never represents a human participant.

const PLAYGROUND: PackedScene = preload("res://tools/screening_playground/screening_playground.tscn")
var demo: Node
var old_size: Vector2i
var old_scale: Vector2i

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	old_size = get_window().size
	old_scale = get_window().content_scale_size
	demo = PLAYGROUND.instantiate()
	add_child(demo)
	await demo.fixture_ready
	await wait_process_frames(6)

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	CoreSystem.audio_manager.stop_all()
	demo.queue_free()
	get_window().size = old_size
	get_window().content_scale_size = old_scale
	await wait_process_frames(3)

func _click(button: Control, horizontal_fraction: float = 0.5) -> void:
	var bounds: Rect2 = button.get_global_rect()
	var point: Vector2 = bounds.position + bounds.size * Vector2(horizontal_fraction, 0.5)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await wait_process_frames(1)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await wait_process_frames(2)

func _reward(low: bool) -> PopupSkillChoice:
	demo.call("load_fixture", "t", "overlap")
	await demo.fixture_ready
	await wait_process_frames(6)
	var board: Board = demo.get("board") as Board
	var game: Node2D = demo.get("main").get_node("Game") as Node2D
	game.call("_set_low_effects", low, false)
	board._on_coordinate_pressed(ScreeningDeck.source(board.run.initialization))
	board._on_coordinate_pressed(ScreeningDeck.target(board.run.initialization))
	var ready: bool = await wait_until(func() -> bool:
		var choice: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		return is_instance_valid(choice) and choice.offer != null, 6.0)
	assert_true(ready)
	await wait_process_frames(12)
	return UIManager.current_popup as PopupSkillChoice

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory: String = "res://.godot/issue192"
	DirAccess.make_dir_recursive_absolute(directory)
	assert_eq(get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png")), OK)

func test_mouse_return_four_size_effect_combinations_preserve_reward_and_replay() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
		for low: bool in [false, true]:
			get_window().size = size
			get_window().content_scale_size = size
			var popup: PopupSkillChoice = await _reward(low)
			if not is_instance_valid(popup): return
			var panel: Control = demo.get_node("Tools/Panel") as Control
			await _click(popup.options.get_child(0) as Control)
			assert_false(popup.confirm_button.disabled)
			var text: String = popup.confirm_button.text
			var board: Board = demo.get("board") as Board
			var run: RunController = board.run
			var before: String = RunSnapshot.canonical(RunSnapshot.capture(run))
			var offer: String = RunSnapshot.canonical(RunSnapshot.offer_data(popup.offer))
			var elapsed: int = int(demo.call("elapsed_ms"))
			# The existing tool overlaps the left of View at 1024px; its right edge is exposed.
			await _click(popup.view_button, 0.95)
			assert_true(popup.viewing_board)
			assert_false(panel.visible)
			assert_true(popup.return_button.is_visible_in_tree())
			assert_true(get_viewport().get_visible_rect().encloses(popup.return_button.get_global_rect()))
			var label: String = "%dx%d-low-%s" % [size.x, size.y, low]
			await _capture(label + "-view")
			if size == Vector2i(1280, 720) and not low:
				for changed: Vector2i in [Vector2i(1024, 640), size]:
					get_window().size = changed
					get_window().content_scale_size = changed
					await wait_process_frames(6)
					assert_false(panel.visible)
					assert_true(get_viewport().get_visible_rect().encloses(popup.return_button.get_global_rect()))
			await _click(popup.return_button)
			assert_false(popup.viewing_board, "mouse must route to Return, not the screening panel")
			assert_true(panel.visible)
			assert_eq(popup.confirm_button.text, text)
			assert_false(popup.confirm_button.disabled)
			assert_eq(RunSnapshot.canonical(RunSnapshot.capture(run)), before)
			assert_eq(RunSnapshot.canonical(RunSnapshot.offer_data(popup.offer)), offer)
			assert_gt(int(demo.call("elapsed_ms")), elapsed)
			await _capture(label + "-returned")
			await _click(popup.confirm_button)
			assert_true(await wait_until(func() -> bool: return bool(demo.get("stopped")), 6.0))
			assert_eq(run.state.ledger.total, 126)
			assert_eq(run.state.rewards.consumed_count, 1)
			assert_eq(run.state.pending_rewards, 0)
			assert_null(run.state.rewards.active_offer)
			assert_eq(run.continuation, &"idle")
			assert_eq(run.state.rule_error, "")
			var acquisitions: int = 0
			for record: Dictionary in run.recorder.records:
				if record.kind == "SkillAcquired": acquisitions += 1
			assert_eq(acquisitions, 1)
			assert_eq(run.recorder.records.back().choices, "1")
			assert_eq(run.state.spawn_history.size(), 0)
			assert_eq(run.state.rules.state.get_piece_count(), 1)
			assert_eq(demo.get("stop_reason"), "fixed_complete")
			assert_eq(demo.get("record_error"), "")
			assert_true(panel.visible)
			var replay: RuleReplay = RuleReplay.new()
			assert_true(replay.replay_file(run.recorder.path), replay.error)
			var sidecar: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(demo.get("summary_path")))) as Dictionary
			assert_null(sidecar.participant)
			assert_null(sidecar.predictions)
			assert_null(sidecar.selection_decision)
			print("ISSUE192_AUTOMATED_RETEST ", label, " record=", run.recorder.path)
			var reset: Button = demo.get_node("Tools/Panel/Rows/Reset") as Button
			await _click(reset)
			await wait_process_frames(30)
			assert_ne((demo.get("board") as Board).run, run)
			assert_true(panel.visible)

func test_hidden_panel_restores_on_popup_destruction_and_fixture_rebuild() -> void:
	var popup: PopupSkillChoice = await _reward(true)
	popup.toggle_board_view()
	await wait_process_frames(3)
	var panel: Control = demo.get_node("Tools/Panel") as Control
	assert_false(panel.visible)
	UIManager.close_popup()
	await wait_process_frames(3)
	assert_true(panel.visible)
	demo.call("load_fixture", "t", "overlap")
	assert_true(panel.visible)
	await demo.fixture_ready
	await wait_process_frames(6)
	popup = await _reward(true)
	popup.toggle_board_view()
	await wait_process_frames(3)
	assert_false(panel.visible)
	var old: RunController = (demo.get("board") as Board).run
	demo.call("load_fixture", "zs", "free")
	assert_true(panel.visible)
	await demo.fixture_ready
	await wait_process_frames(6)
	assert_true(panel.visible)
	assert_true(old.is_retired())
	assert_true(old.recorder.ended)
	assert_null(UIManager.current_popup)
	assert_eq((demo.get("board") as Board).run.state.valid_moves, 0)
