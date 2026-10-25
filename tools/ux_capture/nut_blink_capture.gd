extends Node

## 确定性美术展示盘；所有棋子进入真实规则占格，不伪造UI读数。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/nut_blink_captures"

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
	for y: int in range(9):
		for x: int in range(9):
			var coordinate: Vector2i = Vector2i(x, y)
			if (x * 3 + y * 2) % 4 == 0 and run.state.rules.state.get_piece_at(coordinate) == null:
				run.state.rules.place_piece(coordinate, (x + y * 2) % 5)
	board.run = run
	board.rules = run.state.rules
	GameManager.reset_game(run)
	board.rebuild_view()
	game.call("_set_theme", &"light_toy", false)
	game.call("_set_volume", 0.0, false)
	game.call("_refresh_hud")
	TranslationServer.set_locale("zh_CN")
	var saved_closed: bool = false
	for index: int in range(150):
		for frame: int in range(4): await get_tree().process_frame
		await _capture("frame_%03d" % index)
		if not saved_closed:
			for state: PieceState in board.rules.state.get_snapshot():
				if board.view.get_piece(state.piece_id).nut_visual.eyes_closed:
					await _capture("closed_pose")
					saved_closed = true
					break
	game.call("_set_low_effects", true, false)
	await get_tree().process_frame
	await _capture("low_effects")
	get_tree().quit()

func _capture(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name_text + ".png"))
	if error != OK: push_error(error_string(error))
