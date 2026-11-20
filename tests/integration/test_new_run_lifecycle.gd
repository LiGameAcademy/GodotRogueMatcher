extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
var _game: Node
var _directory: String
var _calls: int
var _bytes: PackedByteArray

class MarkerFaultFiles extends CheckpointFiles:
	func replace(source: String, destination: String) -> Error:
		if source.get_file().begins_with("invalid-"): return ERR_CANT_CREATE
		return super.replace(source, destination)

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_directory = "user://new-run-lifecycle/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_calls = 0
	_bytes = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 23])

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(_game): _game.free()
	await get_tree().process_frame
	await get_tree().process_frame
	_remove(_directory)

func _remove(directory: String) -> void:
	assert_true(directory.begins_with("user://new-run-lifecycle/"))
	for name: String in DirAccess.get_directories_at(directory): _remove(directory.path_join(name))
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func _entropy() -> PackedByteArray:
	_calls += 1
	return _bytes

func _wait(predicate: Callable) -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	assert_true(bool(predicate.call()), "new-run transition reaches expected boundary")

func _saved() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23,
		preload("res://gameplay/progression/stages/stage_config.tres"))
	run.initialize()
	assert_true(SNAPSHOT.save(CheckpointStore.new(_directory), run).ok)
	return run

func _open() -> void:
	_game = GAME.instantiate()
	_game.set("persist_preferences", false)
	_game.set("record_runs", false)
	_game.set("collect_telemetry", false)
	_game.set("show_start_menu", true)
	_game.set("enable_checkpoints", true)
	_game.set("use_snapshot_checkpoints", true)
	_game.set("checkpoint_directory", _directory)
	_board().new_run_seeds.entropy_provider = _entropy
	add_child(_game)
	await _wait(func() -> bool: return (_game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu).visible)

func _board() -> Board:
	return _game.get_node("Board") as Board

func _flow() -> GameCheckpointFlow:
	return _game.get_node("GameCheckpointFlow") as GameCheckpointFlow

func test_menu_preview_and_actual_saved_continue_do_not_request_entropy() -> void:
	var saved: RunController = _saved()
	var state: Dictionary = RunSnapshot.capture(saved)
	await _open()
	assert_eq(_calls, 0)
	assert_eq(_board().new_run_seeds.last_started(), -1)
	await _game.call("_play_from_menu", false)
	assert_eq(_calls, 0)
	assert_eq(_board().run.state.run_id, saved.state.run_id)
	assert_eq(_board().run.state.random_streams.data(), saved.state.random_streams.data())
	assert_eq(RunSnapshot.capture(_board().run).rng, state.rng)
	assert_eq(_board().new_run_seeds.last_started(), 23)

func test_first_actual_play_and_continuous_restart_avoid_only_last_started_seed() -> void:
	await _open()
	assert_eq(_calls, 0)
	await _game.call("_play_from_menu", false)
	assert_eq(_calls, 1)
	assert_eq(_board().run.state.random_streams.master_seed, 23)
	await _wait(func() -> bool: return not _flow().is_busy())
	_game.call("_on_retry_requested")
	await _wait(func() -> bool: return _flow().prompt.is_open())
	_flow().prompt.action_requested.emit(&"confirm")
	await _wait(func() -> bool: return _board().run.state.random_streams.master_seed == 24)
	assert_eq(_calls, 2)
	assert_eq(_board().new_run_seeds.last_started(), 24)

func test_entropy_failure_retains_current_graph_and_saved_bytes_without_confirmation() -> void:
	_saved()
	var path: String = _directory.path_join("primary.json")
	var digest: String = FileAccess.get_sha256(path)
	await _open()
	var original: RunController = _board().run
	var streams: Dictionary = original.state.random_streams.data()
	_bytes = PackedByteArray()
	assert_false(await _game.call("_on_retry_requested"))
	assert_same(_board().run, original)
	assert_false(original.is_retired())
	assert_eq(original.state.random_streams.data(), streams)
	assert_eq(FileAccess.get_sha256(path), digest)
	assert_eq(_board().new_run_seeds.last_started(), -1)
	assert_false(_flow().prompt.is_open())
	assert_eq(_calls, 1)

func test_cancelled_new_run_keeps_previous_seed_and_checkpoint_identity() -> void:
	_saved()
	await _open()
	var original: RunController = _board().run
	var digest: String = FileAccess.get_sha256(_directory.path_join("primary.json"))
	_game.call("_on_retry_requested")
	await _wait(func() -> bool: return _flow().prompt.is_open())
	_flow().prompt.action_requested.emit(&"cancel")
	await _wait(func() -> bool: return not _flow().is_busy())
	assert_same(_board().run, original)
	assert_eq(_board().new_run_seeds.last_started(), -1)
	assert_eq(FileAccess.get_sha256(_directory.path_join("primary.json")), digest)
	assert_eq(_calls, 1)

func test_second_retry_during_confirmation_does_not_take_more_entropy() -> void:
	_saved()
	await _open()
	var original: RunController = _board().run
	_game.call("_on_retry_requested")
	await _wait(func() -> bool: return _flow().prompt.is_open())
	assert_false(await _game.call("_on_retry_requested"))
	assert_eq(_calls, 1)
	assert_same(_board().run, original)
	_flow().prompt.action_requested.emit(&"cancel")
	await _wait(func() -> bool: return not _flow().is_busy())

func test_continue_challenge_keeps_seed_and_does_not_request_entropy() -> void:
	await _open()
	var board: Board = _board()
	var fixed: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23,
		preload("res://gameplay/progression/stages/stage_config.tres"))
	var initial: RunStepResult = fixed.initialize()
	get_tree().paused = false
	board.set_playback_fast(true)
	await board.start_game(fixed.state.rules, false, fixed, initial, "fixture")
	fixed.state.is_game_over = true
	fixed.state.end_reason = &"challenge_completed"
	var completed: StageResult = StageResult.new()
	completed.reason = &"challenge_completed"
	fixed.state.stage.history.append(completed)
	assert_true(fixed.can_continue_challenge())
	get_tree().paused = false
	board.set_playback_fast(true)
	var seed_value: int = fixed.state.random_streams.master_seed
	await _game.call("_continue_challenge")
	assert_eq(_calls, 0)
	assert_same(board.run, fixed)
	assert_eq(board.run.state.random_streams.master_seed, seed_value)
	assert_true(board.run.state.stage.continuing)

func test_incompatible_saved_manifest_is_not_used_as_previous_identity() -> void:
	var run: RunController = _saved()
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	frozen.payload.manifest.engine_build = "unknown-engine"
	var encoded: Dictionary = SNAPSHOT.serialize(frozen.payload)
	assert_true(encoded.ok)
	var store: CheckpointStore = CheckpointStore.new(_directory)
	assert_true(store.begin_run(run.state.run_id).ok)
	var ticket: int = store.stage({"schema": SNAPSHOT.PACKAGE_SCHEMA, "run_id": run.state.run_id,
		"snapshot_json": encoded.bytes.get_string_from_utf8(), "trace": {}}, frozen.payload.manifest)
	assert_gt(ticket, 0)
	assert_true(store.commit(ticket).ok)
	await _open()
	assert_eq(_flow().previous_master_seed(), -1)
	assert_eq(_calls, 0)

func test_failed_invalidation_does_not_claim_or_adopt_prepared_seed() -> void:
	_saved()
	await _open()
	_flow().set("_store", CheckpointStore.new(_directory, MarkerFaultFiles.new()))
	var original: RunController = _board().run
	_game.call("_on_retry_requested")
	await _wait(func() -> bool: return _flow().prompt.is_open())
	_flow().prompt.action_requested.emit(&"confirm")
	await _wait(func() -> bool: return _flow().last_error != "")
	assert_same(_board().run, original)
	assert_false(original.is_retired())
	assert_eq(_board().new_run_seeds.last_started(), -1)
	_flow().prompt.action_requested.emit(&"cancel")
	await _wait(func() -> bool: return not _flow().is_busy())

func test_compatible_saved_identity_causes_collision_correction_without_restoring_it() -> void:
	var saved: RunController = _saved()
	await _open()
	var preview: RunController = _board().run
	assert_eq(_flow().previous_master_seed(), 23)
	assert_eq(_calls, 0)
	assert_same(_board().run, preview)
	_game.call("_on_retry_requested")
	await _wait(func() -> bool: return _flow().prompt.is_open())
	_flow().prompt.action_requested.emit(&"confirm")
	await _wait(func() -> bool: return _board().run != preview)
	assert_eq(_board().run.state.random_streams.master_seed, 24)
	assert_ne(_board().run.state.run_id, saved.state.run_id)
