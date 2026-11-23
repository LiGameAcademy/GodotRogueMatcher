extends GutTest

## Exercises the packed application entry and the pinned CoreSystem scene manager.
const ROLE: Script = preload("res://gameplay/openings/opening_role.gd")
const ROOM: PackedScene = preload("res://ui/preparation_room/preparation_room.tscn")
const ROOM_PATH: String = "res://ui/preparation_room/preparation_room.tscn"
const GAME_PATH: String = "res://gameplay/room_session.tscn"
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const PROGRESS: Script = preload("res://services/run_checkpoint/opening_progress.gd")
var _host: Node
var _directory: String

class BrokenReplacement extends CheckpointFiles:
	var fail_once: bool = false
	func replace(source: String, destination: String) -> Error:
		if fail_once and destination.get_file() == "primary.json":
			fail_once = false
			return ERR_CANT_CREATE
		return super.replace(source, destination)

func before_each() -> void:
	GameFlow.machine = CoreStateMachine.new(GameFlow.Page.BOOT, [0, 1, 2, 3], GameFlow._allowed)
	_host = get_tree().current_scene
	_directory = "user://room-regression/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func after_each() -> void:
	var current: Node = get_tree().current_scene
	get_tree().current_scene = _host
	if current != _host and is_instance_valid(current): current.queue_free()
	UIManager.close_popup()
	get_tree().paused = false
	await get_tree().process_frame
	if DirAccess.dir_exists_absolute(_directory):
		for file: String in DirAccess.get_files_at(_directory):
			DirAccess.remove_absolute(_directory.path_join(file))
		DirAccess.remove_absolute(_directory)

func _room() -> Control:
	var placeholder: Node = Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	GameFlow.travel(GameFlow.Page.ROOM, {"directory": _directory})
	await _until(func() -> bool: return _at(ROOM_PATH))
	var room: Control = get_tree().current_scene
	await _until(func() -> bool: return room.get("_loaded"))
	return room

func _until(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 30000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(condition.call())

func _at(path: String) -> bool:
	var current: Node = get_tree().current_scene
	return is_instance_valid(current) and current.scene_file_path == path

func _playing() -> bool:
	return _at(GAME_PATH) and get_tree().current_scene.get("_has_played") == true

func _run(seed_value: int) -> RunController:
	var rules: BoardRules = BoardRules.new(BoardState.new(9, 9), 5)
	var run: RunController = RunController.new(rules, seed_value, GameModes.CHALLENGE.stage_config)
	run.initialize()
	if run.state.pending_rewards > 0: run.prepare_offer(false)
	return run

func test_replacement_rollback_keeps_old_identity_and_retry_replaces_both_slots() -> void:
	var files: BrokenReplacement = BrokenReplacement.new()
	var store: CheckpointStore = CheckpointStore.new(_directory, files)
	var old: RunController = _run(39)
	var next: RunController = _run(47)
	assert_true((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(old))).ok)
	files.fail_once = true
	assert_false((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(next), {}, true, old.state.run_id)).ok)
	assert_eq(SNAPSHOT.load(store, SNAPSHOT.manifest(old)).run.state.run_id, old.state.run_id)
	assert_false((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(next), {}, true, "another-run")).ok)
	assert_true((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(next), {}, true, old.state.run_id)).ok)
	assert_eq(SNAPSHOT.load(store, SNAPSHOT.manifest(next)).run.state.run_id, next.state.run_id)
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("previous.json")))
	assert_eq(backup.run_id, next.state.run_id)

func _boot() -> void:
	var boot: Node = preload("res://gameplay/flow/game_boot.tscn").instantiate()
	boot.checkpoint_directory = _directory
	get_tree().root.add_child(boot)
	get_tree().current_scene = boot

func test_unreadable_primary_is_not_a_fresh_profile() -> void:
	var files: CheckpointFiles = CheckpointFiles.new()
	assert_eq(files.write_text(_directory.path_join("primary.json"), "broken"), OK)
	_boot()
	await get_tree().process_frame
	assert_true(get_tree().current_scene.get_node("Slot").prompt.is_open())
	assert_eq(GameFlow.machine.current, GameFlow.Page.BOOT)
	assert_false(FileAccess.file_exists(_directory.path_join("opening_progress.json")))

func test_first_boot_and_interrupted_boot_enter_board_directly() -> void:
	_boot()
	if not await _until(_playing):
		var scene: Node = get_tree().current_scene
		var board: Board = scene.get_node_or_null("Board")
		fail_test("Fresh profile did not start playing: %s, flow=%d, paused=%s, board=%s" % [
			scene.scene_file_path, GameFlow.machine.current, get_tree().paused,
			{"run": board.run != null, "input": board.can_selected, "presenting": board.director.is_busy(),
			"hud_visible": scene.get_node("UILayer/HUD").visible, "prompt": scene.get_node("GameCheckpointFlow").prompt.is_open()} if board != null else {}])
		return
	var game: Node = get_tree().current_scene
	var identity: String = game.get_node("Board").run.state.run_id
	assert_eq(GameFlow.machine.current, GameFlow.Page.PLAY)
	assert_eq(game.get_node("Board").run.opening_id, &"standard")
	assert_eq(game.get_node("UILayer/HUD/%CurrentRole").texture, RunController.ROLES.find(&"standard").portrait)
	assert_false(game.release_menu.visible)
	assert_true(game.get_node("Board").can_selected)
	if not await _opening_save_finished(game): return
	game.free()
	GameFlow.machine = CoreStateMachine.new(GameFlow.Page.BOOT, [0, 1, 2, 3], GameFlow._allowed)
	_boot()
	if not await _until(_playing):
		fail_test("Interrupted first run did not resume")
		return
	assert_eq(get_tree().current_scene.get_node("Board").run.state.run_id, identity)

func test_play_scene_entering_tree_after_handoff_accepts_input() -> void:
	# Model a deferred scene attachment after the navigation lock has been released.
	var game: Node = load(GAME_PATH).instantiate()
	game.init_state({"action": "new", "mode": "stage_challenge", "opening": "standard", "directory": _directory})
	GameFlow.machine.try_transition(GameFlow.Page.PLAY)
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	if not await _until(_playing):
		fail_test("Already completed handoff left the opening waiting for another transition")
		return
	assert_true(game.get_node("Board").can_selected)
	await _opening_save_finished(game)

func _opening_save_finished(game: Node) -> bool:
	var checkpoint: GameCheckpointFlow = game.get_node("GameCheckpointFlow")
	if not await _until(func() -> bool: return not checkpoint._saving):
		fail_test("Opening checkpoint write did not finish")
		return false
	return true

func test_relaunch_after_durable_settlement_retires_only_the_same_run() -> void:
	var old: RunController = _run(71)
	var store: CheckpointStore = CheckpointStore.new(_directory)
	assert_true((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(old))).ok)
	var progress: PROGRESS = PROGRESS.new()
	await progress.load_progress(_directory)
	assert_eq(await progress.finish_visit(old.state.run_id, false), "")
	_boot()
	if not await _until(func() -> bool: return _at(ROOM_PATH) and get_tree().current_scene.get("_loaded")):
		fail_test("A settled run must reopen the room")
		return
	assert_false(get_tree().current_scene.get_node("%Continue").visible)
	assert_eq(store.inspect_latest().reason, "run_invalidated")
	var newer: RunController = _run(72)
	assert_true((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(newer))).ok)
	await get_tree().current_scene.get_node("Slot").inspect_slot(_directory)
	assert_eq(store.inspect_latest().run_id, newer.state.run_id)

func test_locked_role_and_real_new_game_result_return() -> void:
	var room: Control = await _room()
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://gameplay/flow/game_boot.tscn")
	assert_null(room.find_child("Board", true, false))
	assert_false(room.get_node("%Continue").visible)
	room.get_node("%Settings").pressed.emit()
	assert_true(room.get_node("PlaybackSettings").panel.visible)
	room.get_node("PlaybackSettings").close()
	room.get_node("%Pool").pressed.emit()
	assert_true(room.get_node("SkillPool").panel.visible)
	room.get_node("SkillPool").close()
	room.get_node("%Practice").pressed.emit()
	assert_true(room.get_node("Tutorial").visible)
	room.get_node("Tutorial").skip_button.pressed.emit()
	assert_true(room.get_node("%Home").visible)
	room.get_node("%New").pressed.emit()
	room.get_node("%Scout").pressed.emit()
	assert_true(room.get_node("%Depart").disabled)
	room.get_node("%Standard").pressed.emit()
	room.get_node("%Depart").pressed.emit()
	if not await _until(_playing):
		fail_test("Standard opening failed to enter play")
		return
	var game: Node = get_tree().current_scene
	var board: Board = game.get_node("Board")
	assert_eq(board.run.opening_id, &"standard")
	board.run.state.stage.index = 1
	board.run.state.ledger.commit(0, 1.0, 1150)
	var fault: String = _directory.path_join("opening_progress.json.tmp")
	assert_eq(DirAccess.make_dir_recursive_absolute(fault), OK)
	board.run.finish_game(&"board_full")
	GameManager.game_overed.emit()
	if not await _until(func() -> bool: return UIManager.current_popup is PopupGameOver and UIManager.current_popup.visible):
		fail_test("Result not shown")
		return
	await get_tree().process_frame
	assert_eq(GameFlow.machine.current, GameFlow.Page.RESULT)
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow")
	assert_eq(flow.last_error, "opening_progress_write_failed")
	assert_true(CheckpointStore.new(_directory).inspect_latest().ok)
	assert_false(flow.opening_progress.unlocked)
	assert_eq(DirAccess.remove_absolute(fault), OK)
	flow.prompt.primary.pressed.emit()
	if not await _until(func() -> bool: return flow.last_error.is_empty() and flow.opening_progress.unlocked):
		fail_test("Settlement retry did not grant the role")
		return
	var result: Control = UIManager.current_popup
	assert_eq(flow.opening_progress.best, 1150)
	assert_eq(result.get_node("Panel/Content/Portraits").get_child_count(), 3)
	for index: int in range(3):
		var role: ROLE = RunController.ROLES.ALL[index + 1]
		var card: Control = result.get_node("Panel/Content/Portraits").get_child(index)
		assert_eq(card.get_node("StartingSkills").text, tr("role.starting_skills") % role.starting_skill_text())
	result.menu_requested.emit()
	result.menu_requested.emit()
	if not await _until(func() -> bool: return _at(ROOM_PATH) and get_tree().current_scene.get("_loaded")):
		fail_test("Result did not return to the preparation room")
		return
	room = get_tree().current_scene
	assert_false(room.get_node("%Continue").visible)
	room.get_node("%New").pressed.emit()
	room.get_node("%Scout").pressed.emit()
	assert_false(room.get_node("%Depart").disabled)

func test_best_400_previews_locked_dyer_and_durable_unlock_starts_bomber() -> void:
	var progress: PROGRESS = PROGRESS.new()
	await progress.load_progress(_directory)
	assert_eq(await progress.finish_visit("first-score", false, 400), "")
	var room: Control = await _room()
	room.get_node("%New").pressed.emit()
	room.get_node("%Dyer").pressed.emit()
	assert_true(room.get_node("%Depart").disabled)
	assert_eq(room.get_node("%Requirement").text, tr("role.target") % [400, 450, 50])
	var slot: GameCheckpointFlow = room.get_node("Slot")
	assert_eq(await slot.opening_progress.finish_visit("second-score", false, 1150), "")
	room.get_node("%Bomber").pressed.emit()
	assert_false(room.get_node("%Depart").disabled)
	room.get_node("%Depart").pressed.emit()
	if not await _until(_playing):
		fail_test("Bomber did not start from the selection screen")
		return
	var board: Board = get_tree().current_scene.get_node("Board")
	assert_eq(board.run.opening_id, &"bomber")
	assert_eq(get_tree().current_scene.get_node("UILayer/HUD/%CurrentRole").texture, RunController.ROLES.find(&"bomber").portrait)
	assert_eq(board.run.state.rewards.acquired.get(&"core_drop"), 1)
	assert_eq(board.run.state.rewards.acquired.get(&"core_manual_detonation"), 1)

func test_changed_slot_rejects_stale_confirmation_and_returns_to_selection() -> void:
	var old: RunController = _run(81)
	var newer: RunController = _run(82)
	var store: CheckpointStore = CheckpointStore.new(_directory)
	assert_true((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(old))).ok)
	var room: Control = await _room()
	room.get_node("%New").pressed.emit()
	room.get_node("%Depart").pressed.emit()
	assert_true((await SNAPSHOT.save_frozen(store, SNAPSHOT.freeze(newer), {}, true, old.state.run_id)).ok)
	room.get_node("Confirm").confirmed.emit()
	if not await _until(func() -> bool: return _at(GAME_PATH) and get_tree().current_scene.get_node("GameCheckpointFlow").prompt.is_open()):
		fail_test("Stale launch should display its recoverable error")
		return
	get_tree().current_scene.get_node("GameCheckpointFlow").prompt.cancel_button.pressed.emit()
	if not await _until(func() -> bool: return _at(ROOM_PATH) and get_tree().current_scene.get("_loaded")):
		fail_test("Could not recover from a failed launch")
		return
	assert_true(get_tree().current_scene.get_node("%Characters").visible)
	assert_eq(store.inspect_latest().run_id, newer.state.run_id)

func test_classic_goes_straight_to_standard_game() -> void:
	var room: Control = await _room()
	room.get_node("%Mode").select(GameModes.ALL.find(GameModes.CLASSIC))
	room.get_node("%New").pressed.emit()
	if not await _until(_playing):
		fail_test("Classic game failed to start: " + get_tree().current_scene.scene_file_path)
		return
	var board: Board = get_tree().current_scene.get_node("Board")
	assert_eq(board.run.state.mode_id(), GameModes.CLASSIC.mode_id)
	assert_eq(board.run.opening_id, &"standard")

func test_cancel_preserves_role_resume_uses_old_run_and_confirm_starts_scout() -> void:
	var old: RunController = _run(57)
	assert_true((await SNAPSHOT.save_frozen(CheckpointStore.new(_directory), SNAPSHOT.freeze(old))).ok)
	var progress: PROGRESS = PROGRESS.new()
	assert_eq(await progress.load_progress(_directory), "")
	assert_eq(await progress.grant(), "")
	var room: Control = await _room()
	assert_true(String(room.get_node("%Continue").text).contains(tr("role.standard")))
	assert_true(String(room.get_node("%Continue").text).contains(tr("room.stage") % 1))
	room.get_node("%New").pressed.emit()
	room.get_node("%Scout").pressed.emit()
	room.get_node("%Depart").pressed.emit()
	var confirm: ConfirmationDialog = room.get_node("Confirm")
	assert_true(confirm.visible)
	confirm.hide()
	confirm.canceled.emit()
	assert_true(room.get_node("%Characters").visible)
	assert_true(room.get_node("%Scout").button_pressed)
	room.get_node("%Back").pressed.emit()
	room.get_node("%Continue").pressed.emit()
	if not await _until(_playing):
		fail_test("Continue did not restore the saved game")
		return
	var game: Node = get_tree().current_scene
	assert_eq(game.get_node("Board").run.state.run_id, old.state.run_id)
	assert_eq(game.get_node("Board").run.opening_id, &"standard")
	assert_eq(game.get_node("UILayer/HUD/%CurrentRole").texture, RunController.ROLES.find(&"standard").portrait)
	await get_tree().process_frame
	await get_tree().process_frame
	game._play_from_menu(true)
	if not await _until(func() -> bool: return _at(ROOM_PATH) and get_tree().current_scene.get("_loaded")):
		fail_test("Could not return from the active run")
		return
	room = get_tree().current_scene
	room.get_node("%New").pressed.emit()
	room.get_node("%Scout").pressed.emit()
	room.get_node("%Depart").pressed.emit()
	room.get_node("Confirm").confirmed.emit()
	if not await _until(_playing):
		fail_test("Confirmed replacement did not enter play")
		return
	var board: Board = get_tree().current_scene.get_node("Board")
	assert_ne(board.run.state.run_id, old.state.run_id)
	assert_eq(board.run.opening_id, &"row_sweep")
	if not await _opening_save_finished(get_tree().current_scene): return
	var restored: Dictionary = SNAPSHOT.load(CheckpointStore.new(_directory), SNAPSHOT.manifest(board.run))
	assert_true(restored.ok, str(restored.reason))
	if restored.ok: assert_eq(restored.run.opening_id, &"row_sweep")

func _tap(control: Control) -> void:
	var position: Vector2 = control.get_viewport().get_final_transform() * control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.position = position
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await wait_process_frames(2)

func _pad(button: JoyButton, extra_presses: int = 0) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		if pressed:
			for _repeat: int in range(extra_presses): Input.parse_input_event(event)
		await wait_process_frames(2)

func test_small_window_touch_previews_lock_and_resumes_original_slot() -> void:
	var old: RunController = _run(61)
	assert_true((await SNAPSHOT.save_frozen(CheckpointStore.new(_directory), SNAPSHOT.freeze(old))).ok)
	var original_canvas: Vector2i = get_window().content_scale_size
	var room: Control = await _room()
	var window: Window = room.get_window()
	var runner_layer: CanvasLayer = get_tree().root.find_child("GutLayer", true, false) as CanvasLayer
	var overlay_visible: bool = runner_layer != null and runner_layer.visible
	if runner_layer != null: runner_layer.hide()
	var previous_size: Vector2i = window.size
	window.size = Vector2i(568, 320)
	await wait_process_frames(4)
	await _tap(room.get_node("%New"))
	assert_true(room.get_node("%Characters").visible)
	await _tap(room.get_node("%Dyer"))
	assert_true(room.get_node("%Dyer").button_pressed)
	assert_true(room.get_node("%Dyer/LockIcon").is_visible_in_tree())
	assert_false(room.get_node("%Standard/LockIcon").visible)
	assert_true(room.get_node("%Depart").disabled)
	await _tap(room.get_node("%Back"))
	window.size = Vector2i(320, 568)
	await wait_process_frames(4)
	await _tap(room.get_node("%New"))
	var transform: Transform2D = window.get_final_transform()
	var physical_window: Rect2 = Rect2(Vector2.ZERO, Vector2(window.size))
	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en_US")
	await wait_process_frames(3)
	var launch: Rect2 = transform * room.get_node("%New").get_global_rect()
	assert_gte(launch.size.y, 44.0)
	await _tap(room.get_node("%Bomber"))
	assert_true(room.get_node("%Bomber").button_pressed)
	assert_lte((transform * room.get_node("%SelectTitle").get_global_rect()).end.x, float(window.size.x))
	TranslationServer.set_locale(previous_locale)
	await wait_process_frames(3)
	assert_true(room.get_node("%Depart").disabled)
	for id: String in ["%Bomber","%Requirement","%Back","%Depart"]:
		assert_true(physical_window.encloses(transform * room.get_node(id).get_global_rect()), id)
	assert_gte((transform * room.get_node("%Back").get_global_rect()).size.y, 44.0)
	await _tap(room.get_node("%Back"))
	await _tap(room.get_node("%Continue"))
	if runner_layer != null: runner_layer.visible = overlay_visible
	if not await _until(_playing):
		window.size = previous_size
		fail_test("Touch did not resume the original slot")
		return
	assert_eq(get_tree().current_scene.get_node("Board").run.state.run_id, old.state.run_id)
	assert_eq(window.content_scale_size, original_canvas)
	window.size = previous_size

func test_gamepad_preview_and_cancel_replacement_preserve_choice() -> void:
	var old: RunController = _run(62)
	assert_true((await SNAPSHOT.save_frozen(CheckpointStore.new(_directory), SNAPSHOT.freeze(old))).ok)
	var progress: PROGRESS = PROGRESS.new()
	await progress.load_progress(_directory)
	assert_eq(await progress.grant(), "")
	var room: Control = await _room()
	# Select New from the home screen using directional focus.
	await _pad(JOY_BUTTON_DPAD_DOWN)
	if not room.get_node("%New").has_focus(): await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	assert_true(room.get_node("%Characters").visible)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	assert_true(room.get_node("%Scout").button_pressed)
	assert_false(room.get_node("%Scout/LockIcon").visible)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	if not room.get_node("%Depart").has_focus(): await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	assert_true(room.get_node("Confirm").visible)
	await _pad(JOY_BUTTON_B)
	assert_false(room.get_node("Confirm").visible)
	assert_true(room.get_node("%Scout").button_pressed)
	assert_true(room.get_node("%Scout").has_focus())
	assert_eq(CheckpointStore.new(_directory).inspect_latest().run_id, old.state.run_id)

func test_keyboard_and_gamepad_cancel_priority() -> void:
	var old: RunController = _run(290)
	assert_true((await SNAPSHOT.save_frozen(CheckpointStore.new(_directory), SNAPSHOT.freeze(old))).ok)
	var room: Control = await _room()
	var mode: OptionButton = room.get_node("%Mode") as OptionButton
	mode.select(GameModes.ALL.find(GameModes.CHALLENGE))
	var confirm: ConfirmationDialog = room.get_node("Confirm") as ConfirmationDialog
	var characters: Control = room.get_node("%Characters") as Control
	for use_pad: bool in [false, true]:
		var device: String = "gamepad" if use_pad else "keyboard"
		(room.get_node("%New") as Button).grab_focus()
		await _menu_action(use_pad, true)
		assert_true(characters.visible, device + " accepts New")
		assert_false(confirm.visible, device + " held confirm cannot trigger the next screen")
		(room.get_node("%Depart") as Button).grab_focus()
		await _menu_action(use_pad, true)
		assert_true(confirm.visible, device + " accepts Depart")
		await _menu_action(use_pad, false)
		assert_false(confirm.visible, device + " closes the modal first")
		assert_true(characters.visible, device + " stays on character selection")
		assert_eq(CheckpointStore.new(_directory).inspect_latest().run_id, old.state.run_id)
		await _menu_action(use_pad, false)
		assert_false(characters.visible, device + " goes back to room home")
		if characters.visible: room.call("_show_home")

func test_repeated_accept_starts_one_session_and_no_board_command(
		use_pad: bool = use_parameters([false, true])) -> void:
	var room: Control = await _room()
	var mode: OptionButton = room.get_node("%Mode") as OptionButton
	mode.select(GameModes.ALL.find(GameModes.CLASSIC))
	var launches: Array[String] = []
	var signal_callback: Callable = func(path: String) -> void: launches.append(path)
	CoreSystem.scene_manager.scene_loading_started.connect(signal_callback)
	(room.get_node("%New") as Button).grab_focus()
	await _menu_action(use_pad, true)
	await _menu_action(not use_pad, true)
	var entered: bool = await _until(_playing)
	CoreSystem.scene_manager.scene_loading_started.disconnect(signal_callback)
	assert_true(entered, "one classic run takes over after repeated confirmation")
	assert_eq(launches, [GAME_PATH])
	if not entered: return
	var game: Node = get_tree().current_scene
	var board: Board = game.get_node("Board") as Board
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var selected: Node = board.selected_piece
	game.call("_toggle_pause")
	assert_true(get_tree().paused)
	for device_is_pad: bool in [false, true]:
		await _menu_action(device_is_pad, true)
		await _menu_action(device_is_pad, false)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_same(board.selected_piece, selected)
	game.call("_toggle_pause")

func _menu_action(use_pad: bool, accept: bool) -> void:
	if use_pad:
		await _pad(JOY_BUTTON_A if accept else JOY_BUTTON_B, 3 if accept else 0)
		return
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_ENTER if accept else KEY_ESCAPE
		key.physical_keycode = key.keycode
		key.pressed = pressed
		Input.parse_input_event(key)
		if pressed and accept:
			var echo: InputEventKey = key.duplicate() as InputEventKey
			echo.echo = true
			for _repeat: int in range(3): Input.parse_input_event(echo)
		await wait_process_frames(2)
