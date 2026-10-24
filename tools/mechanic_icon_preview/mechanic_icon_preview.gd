extends Node

## 首批机制图标的确定性真实选卡/构筑入口；不进入正式菜单，不收集真人数据。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/issue129-icons/captures"
const DROP: Array[StringName] = [&"core_drop", &"line_row_drop", &"line_column_drop"]
const UPGRADE: Array[StringName] = [&"core_supply_up", &"line_row_span", &"line_column_span"]
var game: Node2D
var board: Board
var loading: bool = false
var current: String = "upgrade"
var tools: VBoxContainer
var low: bool = false
var preset_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "技能连珠 · 机制图标预览（#129）"
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	tools = VBoxContainer.new()
	tools.position = Vector2(6, 100)
	layer.add_child(tools)
	for key: String in ["arrival", "upgrade", "build"]:
		var button: Button = Button.new()
		button.text = "登场三卡" if key == "arrival" else ("强化三卡" if key == "upgrade" else "构筑与回退")
		button.pressed.connect(load_case.bind(key))
		tools.add_child(button)
	for title: String in ["中文/English", "明亮/深色", "普通/低特效"]:
		var button: Button = Button.new()
		button.text = title
		button.pressed.connect(toggle.bind(title))
		tools.add_child(button)
	await load_case(current)
	if "--capture-icons" in OS.get_cmdline_user_args(): await capture_suite()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_H:
			tools.visible = not tools.visible

func load_case(key: String) -> void:
	if loading: return
	loading = true
	current = key
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	game = GAME.instantiate() as Node2D
	game.set("show_start_menu", false)
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("enable_debug_fixtures", false)
	game.set("use_external_restart", true)
	game.restart_requested.connect(load_case.bind(key))
	add_child(game)
	board = game.get_node("Board") as Board
	await board.initialized
	board.run.retire()
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	run.initialize()
	if key != "arrival":
		for id: StringName in DROP: AestheticCases.install(run, definition(id))
	if key == "build":
		for id: StringName in UPGRADE + [&"core_radius", &"refill_less"]: AestheticCases.install(run, definition(id))
	run.start_turn()
	if key != "build":
		var skills: Array[SkillDefinition] = []
		for id: StringName in DROP if key == "arrival" else UPGRADE: skills.append(definition(id))
		AestheticCases.offer(run, skills)
	board.run = run
	board.rules = run.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(run)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.refresh_ability_markers()
	game.call("_set_theme", GameThemes.ALL[preset_index].theme_id, false)
	game.call("_set_low_effects", low, false)
	game.call("_refresh_hud")
	board.can_selected = true
	loading = false
	if key != "build": await board.resume_run(run)

func definition(id: StringName) -> SkillDefinition:
	return load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition

func toggle(label: String) -> void:
	if label == "中文/English": TranslationServer.set_locale("en_US" if TranslationServer.get_locale().begins_with("zh") else "zh_CN")
	elif label == "明亮/深色":
		preset_index = 1 - preset_index
		game.call("_set_theme", GameThemes.ALL[preset_index].theme_id, false)
	else:
		low = not low
		game.call("_set_low_effects", low, false)

func capture_suite() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = resolution
			get_window().content_scale_size = resolution
			for theme: int in [0, 1]:
				preset_index = theme
				for key: String in ["arrival", "upgrade", "build"]:
					await load_case(key)
					tools.hide()
					for frame: int in range(45): await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("%s_%s_%d_%d.png" % [key, locale, resolution.x, theme]))
					if error != OK: push_error(error_string(error))
					print("ICON_CAPTURE ", key, " error=", board.run.state.rule_error)
	get_tree().paused = false
	UIManager.close_popup()
	get_tree().quit()
