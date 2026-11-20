extends SceneTree

## Instruments super calls on real scene nodes. No gameplay source is patched by this probe.
var _flow: Node
var _report: Dictionary = {"kind": "instrumented_adoption_profile", "author_feedback": null}
var _measure: bool = false
var _last_frame: int = 0
var _maximum_gap: int = 0
var _frames: int = 0

func _initialize() -> void:
	process_frame.connect(_frame)
	_run.call_deferred()

func _frame() -> void:
	if not _measure: return
	var now: int = Time.get_ticks_usec()
	if _last_frame > 0: _maximum_gap = maxi(_maximum_gap, now - _last_frame)
	_last_frame = now
	_frames += 1

func _run() -> void:
	if DisplayServer.get_name() == "headless": return _fail("gpu_required")
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var game: Node = main.get_node("Game")
	var board: Node = game.get_node("Board")
	var view: Node = board.get_node("BoardView")
	var collection: Node = game.get_node("RunCollection")
	game.set_script(load("res://tools/checkpoint_benchmark/profiles/profiled_game.gd"))
	board.set_script(load("res://tools/checkpoint_benchmark/profiles/profiled_board.gd"))
	view.set_script(load("res://tools/checkpoint_benchmark/profiles/profiled_board_view.gd"))
	collection.set_script(load("res://tools/checkpoint_benchmark/profiles/profiled_collection.gd"))
	get_root().title = "O5 Adoption Profile"
	get_root().add_child(main)
	_flow = game.get_node("GameCheckpointFlow")
	var menu: Node = game.get_node("MenuLayer/ReleaseMenu")
	if not await _wait(func() -> bool: return bool(menu.get("visible")), 15000): return _fail("menu_timeout")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://run_checkpoint/primary.json"))
	var payload: Dictionary = JSON.parse_string(envelope.payload.payload_json)
	if envelope.payload.schema == RunCheckpointSession.PACKAGE_SCHEMA:
		var decoded: Dictionary = preload("res://services/run_checkpoint/checkpoint_float_transport.gd").decode(payload)
		if not decoded.ok: return _fail("invalid_payload_json")
		payload = decoded.data
	var old: RunController = board.get("run") as RunController
	for node: Node in [game, board, view, collection]: node.get("profile").clear()
	_measure = true
	(menu.get_node("%Play") as Button).pressed.emit()
	if not await _wait(func() -> bool: return board.get("run") != old and not bool(_flow.get("restoring")), 25000): return _fail("restore_timeout")
	await process_frame
	await process_frame
	_measure = false
	_report.merge({"renderer": RenderingServer.get_video_adapter_name(), "records": payload.record_seq,
		"snapshot_equal": RunSnapshot.capture(board.get("run")) == payload.state, "old_retired": old.is_retired(),
		"frames": _frames, "maximum_gap_including_adoption_usec": _maximum_gap,
		"game": game.get("profile").duplicate(true), "board": board.get("profile").duplicate(true),
		"view": view.get("profile").duplicate(true), "collection": collection.get("profile").duplicate(true),
		"worker": _flow.get("last_job_metrics").duplicate(true)})
	_report["ok"] = _report.snapshot_equal and _report.old_retired and _report.board.has("adopt_usec") and _report.game.has("restored_callback_usec")
	await RenderingServer.frame_post_draw
	_report["capture_ok"] = get_root().get_texture().get_image().save_png("res://.godot/adoption-profile-restored.png") == OK
	_write()
	_flow.connect("exit_ready", _exit_ready, CONNECT_ONE_SHOT)
	_flow.call("request_exit", "adoption_profile_done")

func _wait(predicate: Callable, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline: await process_frame
	return bool(predicate.call())

func _exit_ready(reason: String) -> void:
	_report["normal_exit_signal"] = reason
	_write()

func _write() -> void:
	var file: FileAccess = FileAccess.open("res://.godot/adoption-profile-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t", true, true))
	file.close()
	print("ADOPTION_PROFILE " + JSON.stringify(_report))

func _fail(reason: String) -> void:
	_report["error"] = reason
	_write()
	quit(1)
