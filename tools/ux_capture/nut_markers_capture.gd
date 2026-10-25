extends Node

## 真实演示盘与显示组件录帧；不将表现时钟写回规则。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/nut_markers_captures"

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
	await board.load_explosion_demo("fixture_line_cross")
	for y: int in range(9):
		for x: int in range(9):
			var coordinate: Vector2i = Vector2i(x, y)
			if (x * 3 + y * 2) % 7 == 0 and board.rules.state.get_piece_at(coordinate) == null:
				board.rules.place_piece(coordinate, (x + y * 2) % 5)
	board.rebuild_view()
	TranslationServer.set_locale("zh_CN")
	game.call("_set_theme", &"light_toy", false)
	game.call("_set_volume", 0.0, false)
	game.call("_refresh_hud")
	board.selected_piece = board.get_cell(Vector2i(2, 4)).piece
	for frame: int in range(60): await get_tree().process_frame
	print("Compact header height: ", (game.get_node("UILayer/HUD/Margin/Rows/Header") as Control).size.y)
	await _save("gameplay")
	for index: int in range(64):
		for frame: int in range(4): await get_tree().process_frame
		await _save("frame_%03d" % index)
	get_tree().paused = true
	await _save("paused")
	get_tree().paused = false
	game.call("_set_low_effects", true, false)
	await _save("low_effects")
	game.call("_set_low_effects", false, false)
	get_window().size = Vector2i(1024, 640)
	get_window().content_scale_size = Vector2i(1024, 640)
	TranslationServer.set_locale("en_US")
	for frame: int in range(30): await get_tree().process_frame
	await _save("english_1024")
	get_tree().quit()

func _save(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name_text + ".png"))
	if error != OK: push_error(error_string(error))
