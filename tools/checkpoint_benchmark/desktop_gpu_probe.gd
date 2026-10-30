extends SceneTree

## Exercises actual rendered menu hit targets using viewport input, in an isolated APPDATA.
## No Windows UI automation or access to another application's window is involved.
var _game: Node
var _flow: Node
var _board: Node
var _report: Dictionary = {"kind": "instrumented_gpu_scene_probe", "author_feedback": null}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	get_root().title = "O5 Checkpoint GPU Probe"
	var main_scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = main_scene.instantiate()
	_game = main.get_node("Game")
	_board = _game.get_node("Board")
	_flow = _game.get_node("GameCheckpointFlow")
	get_root().add_child(main)
	var menu: Node = _game.get_node("MenuLayer/ReleaseMenu")
	if not await _wait(func() -> bool: return bool(menu.get("visible")), 15000): return _fail("menu_timeout")
	var original: RunController = _board.get("run") as RunController
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://run_checkpoint/primary.json"))
	var payload: Dictionary = JSON.parse_string(envelope.payload.payload_json)
	_report["saved_records"] = payload.record_seq
	_report["saved_run_id"] = payload.run_id
	_report["renderer"] = RenderingServer.get_video_adapter_name()
	await _capture("menu")
	await _click(menu.get_node("%Play") as Control)
	if not await _wait(func() -> bool: return bool(_flow.get("restoring")), 5000): return _fail("continue_hit_failed")
	await _capture("loading")
	var prompt: Node = _flow.get_node("CheckpointPrompt")
	await _click(prompt.get_node("%Cancel") as Control)
	if not await _wait(func() -> bool: return not bool(_flow.get("restoring")), 3000): return _fail("cancel_hit_failed")
	_report["cancel_kept_original"] = _board.get("run") == original
	_report["cancel_worker_still_owned"] = _flow.call("is_busy")
	await _capture("cancelled")
	if not await _wait(func() -> bool: return _flow.get("_job") == null, 20000): return _fail("cancel_join_timeout")
	_report["cancelled_job_metrics"] = _flow.get("last_job_metrics").duplicate(true)
	await _click(menu.get_node("%Play") as Control)
	if not await _wait(func() -> bool: return _board.get("run") != original and not bool(_flow.get("restoring")), 20000): return _fail("restore_timeout")
	var active: RunController = _board.get("run") as RunController
	_report["snapshot_equal"] = RunSnapshot.capture(active) == payload.state
	_report["input_enabled"] = _board.get("can_selected")
	_report["old_run_retired"] = original.is_retired()
	_report["load_job_metrics"] = _flow.get("last_job_metrics").duplicate(true)
	await _capture("restored")
	_write()
	_flow.connect("exit_ready", _on_exit_ready, CONNECT_ONE_SHOT)
	_flow.call("request_exit", "gpu_probe_save_and_quit")

func _wait(predicate: Callable, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(predicate.call())

func _click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	get_root().push_input(down, true)
	await process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.position = point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	get_root().push_input(up, true)
	await process_frame

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = get_root().get_texture().get_image()
	var path: String = "res://.godot/desktop-gpu-%s.png" % label
	var error: Error = pixels.save_png(path)
	_report["capture_" + label] = {"path": path, "ok": error == OK, "size": str(pixels.get_size())}

func _on_exit_ready(reason: String) -> void:
	_report["normal_exit_signal"] = reason
	_write()

func _fail(reason: String) -> void:
	_report["error"] = reason
	_write()
	quit(1)

func _write() -> void:
	var file: FileAccess = FileAccess.open("res://.godot/desktop-gpu-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t", true, true))
	file.close()
	print("CHECKPOINT_GPU_REPORT " + JSON.stringify(_report))
