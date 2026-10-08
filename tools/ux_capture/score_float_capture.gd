extends Node

## 固定规则盘面与真实移动，禁用采集；不进入发布包。
const MAIN: PackedScene = preload("res://main.tscn")
var board: Board
var hud: Hud
const OUTPUT: String = "res://production/score_float_m4_light"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var main: Node2D = MAIN.instantiate() as Node2D
	var game: Node2D = main.get_node("Game") as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child(main)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	board.load_explosion_demo()
	board.run.state.explosion.multiplier_level = 3
	board.run.state.explosion.match_extra_level = 2
	hud.show_run(board.run)
	board.selected_piece = board.view.get_piece(board.rules.state.get_piece_id(Vector2i(5, 5)))
	board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.03)
	await _frames(25)
	await _capture("01_main_and_extra")
	await _frames(35)
	await _capture("02_blast_chain")
	await _frames(70)
	if GameManager.score != 120 or not board.run.state.rule_error.is_empty():
		push_error("漂字盘面结算错误")
		get_tree().quit(1)
		return
	print("SCORE_FLOAT_CAPTURE_COMPLETE ", ProjectSettings.globalize_path(OUTPUT))
	get_tree().quit()

func _frames(count: int) -> void:
	for frame: int in range(count): await get_tree().process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(OUTPUT.path_join(name + ".png"))
	if error != OK: push_error(error_string(error))
