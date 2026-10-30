extends GutTest

## Real scene/menu/worker integration; delayed IO below is only a sequencing pressure fixture.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
var _games: Array[Node] = []
var _directories: Array[String] = []
var _frozen_prefix: Array[Dictionary] = []

class SlowFiles extends CheckpointFiles:
	func read_text(path: String) -> Dictionary:
		OS.delay_msec(35)
		return super.read_text(path)

class FailingFiles extends CheckpointFiles:
	var fail_writes: bool = true
	func write_text(path: String, text: String) -> Error:
		return ERR_CANT_CREATE if fail_writes else super.write_text(path, text)

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	for game: Node in _games:
		if is_instance_valid(game): game.free()
	_games.clear()
	await get_tree().process_frame
	for directory: String in _directories:
		if not DirAccess.dir_exists_absolute(directory): continue
		for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
		DirAccess.remove_absolute(directory)
	_directories.clear()

func _directory() -> String:
	var directory: String = "user://desktop-checkpoint-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.append(directory)
	return directory

func _saved_run(frozen: bool = false) -> RunController:
	if frozen and not _frozen_prefix.is_empty():
		var rebuilt: RuleReplay = RuleReplay.new()
		assert_true(rebuilt.restore_prefix(_frozen_prefix), rebuilt.error)
		return rebuilt.run
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23 if frozen else 160)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_scene_test", false)
	if frozen:
		var bot: GreedyBot = GreedyBot.new(100023)
		for index: int in range(500):
			if run.state.rewards.active_offer != null:
				_frozen_prefix = run.recorder.records.duplicate(true)
				return run
			if run.state.is_game_over or not run.state.rule_error.is_empty(): break
			if run.state.phase == RunState.Phase.INPUT: run.execute_command(bot.choose(run))
			else: run.advance()
		assert_not_null(run.state.rewards.active_offer, "normal gameplay must reach the frozen reward fixture")
	return run

func _game(directory: String) -> Node:
	var game: Node = GAME.instantiate()
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("enable_debug_fixtures", false)
	game.set("show_start_menu", true)
	game.set("enable_checkpoints", true)
	game.set("checkpoint_directory", directory)
	_games.append(game)
	add_child(game)
	await _wait(func() -> bool: return (game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu).visible)
	return game

func _wait(predicate: Callable, timeout_ms: int = 10000) -> void:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_true(bool(predicate.call()), "scene operation reached its expected boundary")

func _put(run: RunController, directory: String) -> void:
	var result: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), RunCheckpointCodec.manifest(run)).save(run)
	assert_true(result.ok, result.reason)

func _choice_ready() -> bool:
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	return is_instance_valid(popup) and popup.offer != null and not popup.skill_selected.get_connections().is_empty()

func test_real_continue_button_binds_input_state_and_rebuilds_without_rule_commits() -> void:
	var original: RunController = _saved_run()
	var directory: String = _directory()
	_put(original, directory)
	var expected: Dictionary = RunSnapshot.capture(original)
	var game: Node = await _game(directory)
	var board: Board = game.get_node("Board") as Board
	var old: RunController = board.run
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	assert_true(menu.play_button.text.contains("继续") or menu.play_button.text.contains("Continue"))
	menu.play_button.pressed.emit()
	await _wait(func() -> bool: return board.run != old and not (game.get_node("GameCheckpointFlow") as GameCheckpointFlow).restoring)
	assert_eq(RunSnapshot.capture(board.run), expected)
	assert_true(old.is_retired())
	assert_same(GameManager.run, board.run)
	assert_true(board.can_selected)
	assert_false(get_tree().paused)
	assert_eq(board.view._pieces.size(), board.rules.state.get_piece_count())
	assert_eq((game.get_node("UILayer/HUD") as Hud).displayed_score, board.run.state.ledger.total)
	assert_eq(board.run.recorder.record_appended.get_connections().size(), 0)
	assert_same(board.observation.telemetry, null)
	var before: Dictionary = RunSnapshot.capture(board.run)
	board._commit_buffered_move(0, 1, Vector2i.ZERO, 0, "old_input")
	assert_eq(RunSnapshot.capture(board.run), before)

func test_frozen_continue_shows_original_offer_and_old_popup_callback_cannot_choose_twice() -> void:
	var original: RunController = _saved_run(true)
	var directory: String = _directory()
	_put(original, directory)
	var game: Node = await _game(directory)
	var board: Board = game.get_node("Board") as Board
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	(game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu).play_button.pressed.emit()
	await _wait(_choice_ready)
	assert_eq(RunSnapshot.capture(board.run), RunSnapshot.capture(original))
	assert_false(board.can_selected)
	var old: RunController = board.run
	var old_popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	var id: StringName = old.state.rewards.active_offer.choices[0].skill_id
	flow.restored.connect(func(active: RunController, _fallback: bool) -> void:
		var before: Dictionary = RunSnapshot.capture(active)
		if is_instance_valid(old_popup): old_popup.skill_selected.emit(old.state.rewards.active_offer.offer_id, id)
		assert_eq(RunSnapshot.capture(active), before)
	, CONNECT_ONE_SHOT)
	assert_true(await flow.continue_saved())
	await _wait(_choice_ready)
	assert_ne(board.run, old)
	assert_true(old.is_retired())
	assert_eq(RunSnapshot.capture(board.run), RunSnapshot.capture(original))
	var epoch_before: int = board.run.state.rewards.consumed_count
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	var choice: ChooseSkillCommand = RandomLegalBot.new(1).skill_command(board.run, board.run.state.rewards.active_offer.choices[0].skill_id)
	if choice.selected_color >= 0: popup.color_skill_selected.emit(choice.offer_id, choice.skill_id, choice.selected_color)
	else: popup.skill_selected.emit(choice.offer_id, choice.skill_id)
	await _wait(func() -> bool: return board.run.state.rewards.consumed_count == epoch_before + 1)
	assert_eq(board.run.state.rewards.consumed_count, epoch_before + 1)

func test_cancelled_load_keeps_single_worker_through_new_action_and_rejects_reentry() -> void:
	var saved: RunController = _saved_run()
	var directory: String = _directory()
	_put(saved, directory)
	var game: Node = await _game(directory)
	var board: Board = game.get_node("Board") as Board
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	flow._store = CheckpointStore.new(directory, SlowFiles.new())
	var original: RunController = board.run
	flow.continue_saved()
	await _wait(func() -> bool: return flow._job != null)
	var worker: CheckpointJob = flow._job
	flow.prompt.cancel_button.pressed.emit()
	assert_true(flow.is_busy())
	assert_false(await flow.continue_saved())
	assert_false(await flow.allow_new_run())
	flow._armed = true
	assert_true(original.execute_command(RandomLegalBot.new(9).choose(original)).accepted)
	for index: int in range(10):
		if original.state.phase == RunState.Phase.INPUT and original.continuation == &"idle": break
		if original.state.rewards.active_offer != null: break
		original.advance()
	flow._on_safe_point(original)
	assert_same(flow._job, worker)
	assert_false(flow._saving)
	assert_false(flow._queued.is_empty())
	await _wait(func() -> bool: return flow._job == null and not flow._saving)
	assert_same(board.run, original)
	assert_false(original.is_retired())
	var metadata: Dictionary = CheckpointStore.new(directory).inspect_latest()
	assert_true(metadata.ok, metadata.reason)
	assert_eq(metadata.run_id, saved.state.run_id)

func test_exit_save_can_be_cancelled_without_releasing_worker_ownership() -> void:
	var saved: RunController = _saved_run()
	var directory: String = _directory()
	_put(saved, directory)
	var game: Node = await _game(directory)
	var board: Board = game.get_node("Board") as Board
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	assert_true(await flow.continue_saved())
	flow.exit_ready.disconnect(Callable(game, "_finish_quit"))
	flow._store = CheckpointStore.new(directory, SlowFiles.new())
	flow._last_key = ""
	flow.request_exit("test_close")
	await _wait(func() -> bool: return flow._job != null)
	var worker: CheckpointJob = flow._job
	flow.prompt.cancel_button.pressed.emit()
	assert_true(flow.is_busy())
	assert_false(await flow.continue_saved())
	flow._on_safe_point(board.run)
	assert_same(flow._job, worker)
	await _wait(func() -> bool: return flow._job == null and not flow._saving)
	assert_false(flow.closing)
	assert_false(flow.restoring)
	assert_true(board.can_selected)
	assert_true(CheckpointStore.new(directory).inspect_latest().ok)

func test_exit_failure_keeps_old_file_and_retry_reaches_the_exit_signal() -> void:
	var saved: RunController = _saved_run()
	var directory: String = _directory()
	_put(saved, directory)
	var game: Node = await _game(directory)
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	assert_true(await flow.continue_saved())
	flow.exit_ready.disconnect(Callable(game, "_finish_quit"))
	var files: FailingFiles = FailingFiles.new()
	flow._store = CheckpointStore.new(directory, files)
	flow._last_key = ""
	var previous: String = FileAccess.get_sha256(directory.path_join("primary.json"))
	flow.request_exit("test_save_failure")
	await _wait(func() -> bool: return flow.prompt.leave_old.visible)
	assert_eq(FileAccess.get_sha256(directory.path_join("primary.json")), previous)
	assert_true(flow.closing)
	assert_false((game.get_node("Board") as Board).can_selected)
	files.fail_writes = false
	var exits: Array[String] = []
	flow.exit_ready.connect(func(reason: String) -> void: exits.append(reason))
	flow.prompt.primary.pressed.emit()
	await _wait(func() -> bool: return not exits.is_empty())
	assert_eq(exits, ["test_save_failure"])
	assert_true(CheckpointStore.new(directory).inspect_latest().ok)

func test_new_run_requires_confirmation_and_old_identity_is_invalid_before_new_save() -> void:
	var saved: RunController = _saved_run()
	var directory: String = _directory()
	_put(saved, directory)
	var game: Node = await _game(directory)
	var board: Board = game.get_node("Board") as Board
	var initial: RunController = board.run
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	menu.new_button.pressed.emit()
	await _wait(func() -> bool: return flow.prompt.is_open())
	flow.prompt.cancel_button.pressed.emit()
	await _wait(func() -> bool: return menu.visible and not flow.is_busy())
	assert_same(board.run, initial)
	assert_eq(CheckpointStore.new(directory).inspect_latest().run_id, saved.state.run_id)
	menu.new_button.pressed.emit()
	await _wait(func() -> bool: return flow.prompt.is_open())
	flow.prompt.primary.pressed.emit()
	await _wait(func() -> bool: return bool(game.get("_has_played")) and board.run != initial and flow._job == null and not flow._saving)
	assert_ne(board.run.state.run_id, saved.state.run_id)
	assert_eq(CheckpointStore.new(directory).begin_run(saved.state.run_id).reason, "run_invalidated")
	var metadata: Dictionary = CheckpointStore.new(directory).inspect_latest()
	assert_true(metadata.ok, metadata.reason)
	assert_eq(metadata.run_id, board.run.state.run_id)

func test_pending_challenge_victory_can_continue_and_save_same_run() -> void:
	var config: StageConfig = StageConfig.new()
	config.targets = [1]
	config.pressure_intervals = [2]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, config)
	run.initialize("fixture_f6")
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_continuation_fixture", false)
	var directory: String = _directory()
	_put(run, directory)
	var board: Board = Board.new()
	board.run = run
	var flow: GameCheckpointFlow = preload("res://gameplay/game_checkpoint_flow.tscn").instantiate() as GameCheckpointFlow
	add_child_autofree(flow)
	flow.configure(board, true, directory)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	command.target = Vector2i(5, 4)
	assert_true(run.execute_command(command).accepted)
	for index: int in range(10):
		if run.state.is_game_over: break
		run.advance()
	assert_true(run.can_continue_challenge())
	flow.terminal(run)
	assert_true(CheckpointStore.new(directory).inspect_latest().ok)
	var continuation: ContinueChallengeCommand = ContinueChallengeCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	assert_true(run.execute_command(continuation).accepted)
	assert_eq(run.advance().kind, &"offer")
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var saved: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), policy).save(run)
	assert_true(saved.ok, saved.reason)
	var loaded: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), policy).load_candidate()
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok:
		assert_eq(RunSnapshot.capture(loaded.run), RunSnapshot.capture(run))
		assert_eq(loaded.run.state.run_id, run.state.run_id)
	board.free()

func test_old_movement_and_buffered_callbacks_cannot_modify_adopted_run() -> void:
	var saved: RunController = _saved_run()
	var directory: String = _directory()
	_put(saved, directory)
	var game: Node = await _game(directory)
	var board: Board = game.get_node("Board") as Board
	var flow: GameCheckpointFlow = game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	var old: RunController = board.run
	var generation: int = board._generation
	var command: MovePieceCommand = RandomLegalBot.new(1).choose(old) as MovePieceCommand
	assert_not_null(command)
	if command == null: return
	(game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu).close()
	get_tree().paused = false
	board.selected_piece = board.view.get_piece(command.piece_id)
	board.move_selected_piece(board.get_cell(command.target), 2.0)
	assert_true(board.director.is_busy())
	assert_true(await flow.continue_saved())
	var state: Dictionary = RunSnapshot.capture(board.run)
	board._commit_buffered_move(generation, command.piece_id, command.target, 0, "stale_move")
	assert_eq(old.execute_command(command).reason, "run_closed")
	await get_tree().create_timer(2.1).timeout
	assert_eq(RunSnapshot.capture(board.run), state)
	assert_eq(board.view._pieces.size(), board.rules.state.get_piece_count())
