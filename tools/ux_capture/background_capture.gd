extends Node

## Real Compatibility renders and frame intervals; fixtures are never human balance data.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/issue30_captures"
const WARMUP: int = 90
const SAMPLES: int = 240

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var game: Node2D = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("show_start_menu", false)
	add_child(game)
	var board: Board = game.get_node("Board") as Board
	await board.initialized
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_dye")
	board.run = run
	board.rules = run.state.rules
	GameManager.reset_game(run)
	board.rebuild_view()
	game.call("_refresh_hud")
	game.call("_set_volume", 0.0, false)
	get_tree().paused = false
	var background: GameBackground = game.get_node("ColorRect") as GameBackground
	if OS.get_cmdline_user_args().has("--demo"):
		await _demo(game, background)
		get_tree().quit()
		return
	var report: Dictionary = {"engine": Engine.get_version_info(), "os": OS.get_name(), "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(), "method": "frame_post_draw intervals, vsync disabled, uncapped; desktop fixture, not GPU timings", "warmup_frames": WARMUP, "sample_frames": SAMPLES, "rows": []}
	for preset: GameTheme in GameThemes.ALL:
		game.call("_set_theme", preset.theme_id, false)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			get_window().size = resolution
			get_window().content_scale_size = resolution
			for enabled: bool in [false, true]:
				game.call("_set_background_motion", enabled, false)
				for _frame: int in range(WARMUP): await RenderingServer.frame_post_draw
				var values: Array[float] = []
				var previous: int = Time.get_ticks_usec()
				for _sample: int in range(SAMPLES):
					await RenderingServer.frame_post_draw
					var now: int = Time.get_ticks_usec()
					values.append((now - previous) / 1000.0)
					previous = now
				values.sort()
				var row: Dictionary = {"theme": String(preset.theme_id), "width": resolution.x, "height": resolution.y, "enabled": enabled, "p50_ms": values[119], "p95_ms": values[227], "p99_ms": values[237], "samples_sorted_ms": values}
				report["rows"].append(row)
				print("BACKGROUND_FRAME ", JSON.stringify({"theme": row.theme, "width": row.width, "enabled": enabled, "p50": row.p50_ms, "p95": row.p95_ms, "p99": row.p99_ms}))
		get_window().size = Vector2i(1280, 720)
		get_window().content_scale_size = Vector2i(1280, 720)
		game.call("_set_background_motion", true, false)
		background.phase = 12.0
		background._process(0.0)
		await _capture(String(preset.theme_id) + "_flow")
		background.respond_to_score(150)
		await _capture(String(preset.theme_id) + "_response")
		game.call("_set_low_effects", true, false)
		await _capture(String(preset.theme_id) + "_static")
		game.call("_set_low_effects", false, false)
	var file: FileAccess = FileAccess.open(OUTPUT.path_join("frame_times.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write background benchmark")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	get_tree().quit()

func _capture(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name_text + ".png"))
	if error != OK: push_error(error_string(error))

## Fixed 0.1-second visual steps are encoded at 10 FPS, preserving the configured speed.
func _demo(game: Node2D, background: GameBackground) -> void:
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("demo")))
	var frame: int = 0
	for preset: GameTheme in GameThemes.ALL:
		game.call("_set_theme", preset.theme_id, false)
		background.reset_visual()
		background.set_process(false)
		for index: int in range(90):
			if index == 40:
				background.set_process(true)
				background.respond_to_score(150)
				background.set_process(false)
			background._process(0.1)
			await RenderingServer.frame_post_draw
			var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("demo/%04d.png" % frame))
			if error != OK: push_error(error_string(error))
			frame += 1
