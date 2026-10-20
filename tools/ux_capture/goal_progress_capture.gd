extends Node

## 固定挑战盘面、真实移动与真实渲染；不记录试玩样本，不进入发布包。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://production/goal_progress"
var game: Node2D
var board: Board
var hud: Hud

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = GAME.instantiate() as Node2D
	game.set("show_start_menu", false)
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child(game)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	var config: StageConfig = StageConfig.new()
	config.targets = [200, 150]
	config.pressure_intervals = [4, 4]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7, config)
	run.initialize("fixture_dye")
	board.run = run
	board.rules = run.state.rules
	GameManager.reset_game(run)
	ItemEffectSystem.placed_items.clear()
	board.rebuild_view()
	game.call("_refresh_hud")
	game.call("_set_fast", false, false)
	game.call("_set_low_effects", false, false)
	game.call("_set_volume", 0.0, false)
	get_tree().paused = false
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = resolution
			await _frames(8)
			await _capture("hud_%s_%d" % [locale, resolution.x])
			hud.piece_pool.open()
			await _frames(8)
			await _capture("pool_%s_%d" % [locale, resolution.x])
			hud.piece_pool.close()
	TranslationServer.set_locale("zh_CN")
	get_window().size = Vector2i(1280, 720)
	await _frames(8)
	board.selected_piece = board.get_cell(Vector2i(4, 6)).piece
	board.move_selected_piece(board.get_cell(Vector2i(4, 4)), 0.01)
	for frame: int in range(300):
		if hud.goal_progress.motes.get_child_count() > 0: break
		await _frames(1)
	await get_tree().create_timer(0.18).timeout
	await _capture("score_flight")
	await get_tree().create_timer(0.3).timeout
	await _capture("score_fill_glow")
	for frame: int in range(300):
		if board.can_selected: break
		await _frames(1)
	await _capture("score_settled")
	if hud.goal_progress.current_label.text != str(run.state.ledger.total) or run.state.ledger.total != 105:
		push_error("Goal capture failed to align with ledger")
		get_tree().quit(1)
		return
	print("GOAL_PROGRESS_CAPTURE_COMPLETE ", ProjectSettings.globalize_path(OUTPUT))
	get_tree().quit()

func _frames(count: int) -> void:
	for frame: int in range(count): await get_tree().process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(OUTPUT.path_join(name + ".png"))
	if error != OK: push_error(error_string(error))
