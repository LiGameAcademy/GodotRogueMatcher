extends GutTest

## Actual Game consumers with a controlled browser adapter; not Web platform evidence.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
const PERSISTENCE: Script = preload("res://tests/support/web_telemetry_persistence.gd")
const SUPPORT: Script = preload("res://services/telemetry/web_collection_support.gd")
var _game: Node

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	if is_instance_valid(_game): _game.free()
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame

func test_game_restore_and_restart_keep_the_browser_adapter_and_observation_attachment() -> void:
	var support: SUPPORT = SUPPORT.new(BACKEND.new(PERSISTENCE.new()))
	assert_true((await support.open()).ok)
	_game = GAME.instantiate()
	_game.set("collect_telemetry", false)
	_game.set("record_runs", false)
	_game.set("persist_preferences", false)
	_game.set("show_start_menu", false)
	_game.set("enable_debug_fixtures", false)
	add_child(_game)
	var board: Board = _game.get_node("Board") as Board
	assert_true(await _wait(func() -> bool: return board.can_selected and board.run != null))
	var collection: RunCollection = _game.get_node("RunCollection") as RunCollection
	collection.set("_web", support)
	var factory: TelemetryFactory = TelemetryFactory.new("s-web-game-parent")
	factory.sink_factory = support.make_sink
	collection.configure("web_playtest", factory, false)
	var source: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	source.initialize()
	source.recorder = RunRecorder.new()
	factory.attach(source.recorder, source.state.run_id)
	source.recorder.begin(source, "human", false, "web_game_test")
	collection.bind(source)
	assert_true(await _wait(func() -> bool: return not support.pending()))
	var trace: Dictionary = collection.checkpoint_trace(source)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(source.recorder.records), replay.error)
	_game.call("_suspend_collection")
	assert_true(board.adopt_checkpoint(replay.run))
	board.game_mode = GameModes.find(replay.run.state.mode_id())
	var flow: GameCheckpointFlow = _game.get_node("GameCheckpointFlow") as GameCheckpointFlow
	flow.last_resume_context = {"checkpoint_id": "web-game-point", "trace": trace, "prepared": {"session_id": "s-web-game-child", "record_file": false}}
	_game.set("collect_telemetry", true)
	_game.call("_on_checkpoint_restored", replay.run, false)
	assert_true(collection.enabled)
	assert_same(board.telemetry_factory, collection.factory)
	assert_not_null(board.observation.telemetry)
	assert_eq(board.observation.telemetry.events[0].event_name, "run_resumed")
	assert_true(board.observation.telemetry.events[0].resume.lineage_known)
	var restored_id: String = board.run.state.run_id
	collection.suspend_for_checkpoint()
	var menu: ReleaseMenu = _game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	menu.play_requested.emit(true)
	assert_true(await _wait(func() -> bool: return board.run != null and board.run.state.run_id != restored_id and board.can_selected))
	assert_true(collection.enabled)
	assert_same(board.telemetry_factory, collection.factory)
	assert_eq(board.observation.telemetry.events[0].event_name, "run_started")
	assert_string_starts_with(board.observation.telemetry.sink.get("path"), "telemetry/")
	collection.close("test_completed")
	assert_true(await _wait(func() -> bool: return not support.pending()))
	assert_eq(support.error(), "")

func _wait(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return bool(predicate.call())
