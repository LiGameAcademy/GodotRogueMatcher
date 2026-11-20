extends GutTest

## Exercises the packed application entry and the pinned CoreSystem scene manager.
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
	var deadline: int = Time.get_ticks_msec() + 9000
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
		fail_test("Fresh profile did not start playing")
		return
	var game: Node = get_tree().current_scene
	var identity: String = game.get_node("Board").run.state.run_id
	assert_eq(GameFlow.machine.current, GameFlow.Page.PLAY)
	assert_eq(game.get_node("Board").run.opening_id, &"standard")
	assert_false(game.release_menu.visible)
	await _until(func() -> bool: return not game.get_node("GameCheckpointFlow")._saving)
	game.free()
	GameFlow.machine = CoreStateMachine.new(GameFlow.Page.BOOT, [0, 1, 2, 3], GameFlow._allowed)
	_boot()
	if not await _until(_playing):
		fail_test("Interrupted first run did not resume")
		return
	assert_eq(get_tree().current_scene.get_node("Board").run.state.run_id, identity)

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
	board.run.finish_game(&"board_full")
	GameManager.game_overed.emit()
	if not await _until(func() -> bool: return UIManager.current_popup is PopupGameOver and UIManager.current_popup.visible):
		fail_test("Result not shown")
		return
	await get_tree().process_frame
	UIManager.current_popup.menu_requested.emit()
	if not await _until(func() -> bool: return _at(ROOM_PATH) and get_tree().current_scene.get("_loaded")):
		fail_test("Result did not return to the preparation room")
		return
	room = get_tree().current_scene
	assert_false(room.get_node("%Continue").visible)
	room.get_node("%New").pressed.emit()
	room.get_node("%Scout").pressed.emit()
	assert_false(room.get_node("%Depart").disabled)

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
		fail_test("Classic game failed to start")
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
	assert_true(String(room.get_node("%Continue").text).contains(tr("opening.standard")))
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
	var restored: Dictionary = SNAPSHOT.load(CheckpointStore.new(_directory), SNAPSHOT.manifest(board.run))
	assert_true(restored.ok)
	if restored.ok: assert_eq(restored.run.opening_id, &"row_sweep")
