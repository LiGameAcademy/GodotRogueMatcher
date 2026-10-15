extends Node

## Run the same fixed board before/after #28; screenshots are not balance samples.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/issue28_captures"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var game: Node = GAME.instantiate()
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
	var before: bool = OS.get_cmdline_user_args().has("--before")
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = size
			get_window().content_scale_size = size
			await _capture("%s_%s_%d" % ["before" if before else "after", locale, size.x])
			if not before:
				game.call("_open_settings")
				await _capture("settings_%s_%d" % [locale, size.x])
				game.get_node("PlaybackSettings").call("close")
	get_tree().quit()

func _capture(name_text: String) -> void:
	for _frame: int in range(10): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(OUTPUT.path_join(name_text + ".png"))
	if error != OK: push_error(error_string(error))
