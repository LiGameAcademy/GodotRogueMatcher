extends Node

## 分片机制图标的确定性真实选卡/构筑入口；不进入正式菜单，不收集真人数据。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/issue129-match-bonus-icons/captures"
const MATCH_BONUS: Array[StringName] = [&"match_extra", &"precision_reward", &"longline_reward"]
const FUSE_BASE: Array[StringName] = [&"fuse_match_plant", &"fuse_relay"]
const DYE_UPGRADES: Array[StringName] = [&"dye_target_up", &"dye_chain_depth"]
const ECONOMY: Array[StringName] = [&"refill_less", &"refill_more", &"score_multiplier"]
const LABELS: Dictionary[String, String] = {
	"arrival": "登场三卡", "upgrade": "强化三卡", "build": "构筑与回退",
	"economy": "供给与倍率", "economy_build": "供给构筑",
	"dye": "染色接续", "dye_upgrades": "染色强化", "dye_build": "染色构筑",
	"fuse": "布雷与传递", "fuse_capacity": "传递接力", "fuse_build": "引信构筑",
	"bonus": "五连额外分", "bonus_build": "收益与倍率构筑",
}
const DROP: Array[StringName] = [&"core_drop", &"line_row_drop", &"line_column_drop"]
const UPGRADE: Array[StringName] = [&"core_supply_up", &"line_row_span", &"line_column_span"]
var game: Node2D
var board: Board
var loading: bool = false
var current: String = "bonus"
var tools_panel: PanelContainer
var tools: VBoxContainer
var low: bool = false
var preset_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "技能连珠 · 五连收益图标（#129）"
	var layer: CanvasLayer = CanvasLayer.new()
	# 仅测试工具置于HUD/弹窗之上；H收起后检查完整卡面。
	layer.layer = 200
	add_child(layer)
	tools_panel = PanelContainer.new()
	tools_panel.position = Vector2(6, 100)
	var backdrop: StyleBoxFlat = StyleBoxFlat.new()
	backdrop.bg_color = Color(0.12, 0.1, 0.16, 1.0)
	backdrop.set_content_margin_all(4.0)
	tools_panel.add_theme_stylebox_override("panel", backdrop)
	layer.add_child(tools_panel)
	tools = VBoxContainer.new()
	tools_panel.add_child(tools)
	var case_grid: GridContainer = GridContainer.new()
	case_grid.columns = 2
	tools.add_child(case_grid)
	for key: String in LABELS:
		var button: Button = Button.new()
		button.text = LABELS[key]
		button.pressed.connect(load_case.bind(key))
		case_grid.add_child(button)
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
			tools_panel.visible = not tools_panel.visible

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
	# 供给卡从中期候选池开放；夹具从第4次奖励起，不放宽正式合法条件。
	if key in ["economy", "economy_build"]: run.state.rewards.consumed_count = 3
	if key in ["upgrade", "build"]:
		for id: StringName in DROP: AestheticCases.install(run, definition(id))
	if key == "build":
		for id: StringName in UPGRADE + [&"core_radius", &"color_weight_up"]: AestheticCases.install(run, definition(id))
	if key == "economy_build":
		for id: StringName in ECONOMY + [&"color_weight_up"]: AestheticCases.install(run, definition(id))
	if key in ["dye_upgrades", "dye_build"]: AestheticCases.install(run, definition(&"match_dye_echo"))
	if key == "dye_build":
		for id: StringName in DYE_UPGRADES + [&"color_weight_up"]: AestheticCases.install(run, definition(id))
	if key in ["fuse", "fuse_capacity", "fuse_build"]:
		for id: StringName in [&"core_drop", &"assign_fuse"]: AestheticCases.install(run, definition(id))
	if key == "fuse_capacity": AestheticCases.install(run, definition(&"fuse_relay"))
	if key == "fuse_build":
		for id: StringName in FUSE_BASE + [&"relay_capacity", &"relay_capacity", &"color_weight_up"]: AestheticCases.install(run, definition(id))
	if key == "bonus_build":
		for id: StringName in [&"match_extra", &"precision_reward", &"precision_reward", &"longline_reward", &"longline_reward", &"longline_reward", &"score_multiplier", &"color_weight_up"]:
			AestheticCases.install(run, definition(id))
	run.start_turn()
	if key not in ["build", "economy_build", "dye_build", "fuse_build", "bonus_build"]:
		var skills: Array[SkillDefinition] = []
		var ids: Array[StringName] = UPGRADE
		if key == "arrival": ids = DROP
		elif key == "economy": ids = ECONOMY
		elif key == "dye": ids = [&"match_dye_echo"]
		elif key == "dye_upgrades": ids = DYE_UPGRADES
		elif key == "fuse": ids = FUSE_BASE
		elif key == "fuse_capacity": ids = [&"relay_capacity"]
		elif key == "bonus": ids = MATCH_BONUS
		for id: StringName in ids: skills.append(definition(id))
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
	if key not in ["build", "economy_build", "dye_build", "fuse_build", "bonus_build"]: await board.resume_run(run)

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
				for key: String in ["bonus", "bonus_build"]:
					await load_case(key)
					tools_panel.hide()
					for frame: int in range(45): await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("%s_%s_%d_%d.png" % [key, locale, resolution.x, theme]))
					if error != OK: push_error(error_string(error))
					print("ICON_CAPTURE ", key, " error=", board.run.state.rule_error)
	tools_panel.show()
	for frame: int in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var toolbar_fits: bool = get_viewport().get_visible_rect().encloses(tools_panel.get_global_rect())
	print("ICON_TOOLBAR_FITS ", toolbar_fits)
	if not toolbar_fits: push_error("preview toolbar exceeds viewport")
	var toolbar_error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("tools_en_US_1024_1.png"))
	if toolbar_error != OK: push_error(error_string(toolbar_error))
	get_tree().paused = false
	UIManager.close_popup()
	get_tree().quit()
