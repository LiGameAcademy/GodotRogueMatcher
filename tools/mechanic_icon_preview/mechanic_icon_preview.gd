extends Node

## 分片机制图标的确定性真实选卡/构筑入口；不进入正式菜单，不收集真人数据。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/issue129-cross-sweep-icons/captures"
const CROSS_SWEEP: Array[StringName] = [&"line_cross_upgrade", &"line_clear_score"]
const TRANSFORM: Array[StringName] = [&"instant_core_transform", &"instant_row_transform", &"instant_column_transform"]
const FUSE_PAYLOAD: Array[StringName] = [&"assign_fuse", &"fuse_capacity", &"core_fuse_payload"]
const MANUAL: Array[StringName] = [&"core_manual_detonation", &"line_manual_clear"]
const BLAST_PAYOFF: Array[StringName] = [&"blast_extra", &"blast_chain_bonus", &"blast_refill_relief"]
const MATCH_BONUS: Array[StringName] = [&"match_extra", &"precision_reward", &"longline_reward"]
const FUSE_BASE: Array[StringName] = [&"fuse_match_plant", &"fuse_relay"]
const DYE_UPGRADES: Array[StringName] = [&"dye_target_up", &"dye_chain_depth"]
const ECONOMY: Array[StringName] = [&"refill_less", &"refill_more", &"score_multiplier"]
const LABELS: Dictionary[String, String] = {
	"cross_sweep": "十字与扫线收获", "cross_sweep_build": "十字与收获构筑",
	"transform": "即时改装三卡", "transform_core": "爆壳改装结果",
	"transform_row": "横扫改装结果", "transform_column": "纵扫改装结果",
	"fuse_payload": "赋能扩容装填", "fuse_payload_build": "扩容与装填构筑",
	"manual": "主动两卡", "manual_build": "主动与轮廓",
	"arrival": "登场三卡", "upgrade": "强化三卡", "build": "构筑与回退",
	"economy": "供给与倍率", "economy_build": "供给构筑",
	"dye": "染色接续", "dye_upgrades": "染色强化", "dye_build": "染色构筑",
	"fuse": "布雷与传递", "fuse_capacity": "传递接力", "fuse_build": "引信构筑",
	"bonus": "五连额外分", "bonus_build": "收益与倍率构筑",
	"blast_payoff": "爆破收益三卡", "blast_payoff_build": "爆破收益构筑",
}
const DROP: Array[StringName] = [&"core_drop", &"line_row_drop", &"line_column_drop"]
const UPGRADE: Array[StringName] = [&"core_supply_up", &"line_row_span", &"line_column_span"]
var game: Node2D
var board: Board
var loading: bool = false
var current: String = "cross_sweep"
var tools_panel: PanelContainer
var tools: VBoxContainer
var low: bool = false
var preset_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "技能连珠 · 十字与扫线收益（#129）"
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
	case_grid.columns = 3
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
	if key in ["blast_payoff", "blast_payoff_build"]:
		for id: StringName in [&"core_drop", &"assign_fuse"]: AestheticCases.install(run, definition(id))
	if key == "blast_payoff_build":
		for id: StringName in [&"blast_extra", &"blast_extra", &"blast_chain_bonus", &"blast_chain_bonus", &"blast_chain_bonus", &"blast_refill_relief", &"match_extra", &"color_weight_up"]:
			AestheticCases.install(run, definition(id))
	if key in ["manual", "manual_build"]:
		for id: StringName in DROP + [&"assign_fuse"]: AestheticCases.install(run, definition(id))
	if key == "manual_build":
		for id: StringName in MANUAL: AestheticCases.install(run, definition(id))
		# 同色同轮廓对照；只通过正式规则入口放置、附引信，不伪造状态组合。
		for color: int in range(5):
			var plain: PieceState = run.state.rules.place_piece(Vector2i(color + 2, 3), color)
			var fused: PieceState = run.state.rules.place_piece(Vector2i(color + 2, 4), color)
			if plain == null or fused == null or not run.abilities.assign_fuse(fused.piece_id):
				run.report_error("outline fixture placement failed")
	if key in ["fuse_payload", "fuse_payload_build"]:
		for x: int in range(9):
			if run.state.rules.state.get_piece_id(Vector2i(x, 4)) == 0:
				run.state.rules.place_piece(Vector2i(x, 4), x % 5)
		for id: StringName in [&"core_drop", &"assign_fuse"]: AestheticCases.install(run, definition(id))
	if key == "fuse_payload_build":
		for id: StringName in [&"fuse_capacity", &"fuse_capacity", &"core_fuse_payload", &"fuse_match_plant", &"color_weight_up"]:
			AestheticCases.install(run, definition(id))
	if key.begins_with("transform"):
		# 即时转化从第3次奖励起；保持正式最低奖励条件。
		run.state.rewards.consumed_count = 2
		for x: int in range(9):
			if run.state.rules.state.get_piece_id(Vector2i(x, 4)) == 0:
				run.state.rules.place_piece(Vector2i(x, 4), x % 5)
		if key != "transform":
			var index: int = 0 if key == "transform_core" else (1 if key == "transform_row" else 2)
			AestheticCases.install(run, definition(TRANSFORM[index]))
	if key in ["cross_sweep", "cross_sweep_build"]:
		for id: StringName in [&"line_row_drop", &"line_column_drop"]: AestheticCases.install(run, definition(id))
	if key == "cross_sweep_build":
		for id: StringName in [&"line_manual_clear", &"line_cross_upgrade", &"line_clear_score", &"line_clear_score", &"color_weight_up"]:
			AestheticCases.install(run, definition(id))
	run.start_turn()
	if key not in ["build", "economy_build", "dye_build", "fuse_build", "bonus_build", "blast_payoff_build", "manual_build", "fuse_payload_build", "transform_core", "transform_row", "transform_column", "cross_sweep_build"]:
		var skills: Array[SkillDefinition] = []
		var ids: Array[StringName] = UPGRADE
		if key == "cross_sweep": ids = CROSS_SWEEP
		elif key == "transform": ids = TRANSFORM
		elif key == "fuse_payload": ids = FUSE_PAYLOAD
		elif key == "manual": ids = MANUAL
		elif key == "arrival": ids = DROP
		elif key == "economy": ids = ECONOMY
		elif key == "dye": ids = [&"match_dye_echo"]
		elif key == "dye_upgrades": ids = DYE_UPGRADES
		elif key == "fuse": ids = FUSE_BASE
		elif key == "fuse_capacity": ids = [&"relay_capacity"]
		elif key == "bonus": ids = MATCH_BONUS
		elif key == "blast_payoff": ids = BLAST_PAYOFF
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
	if key not in ["build", "economy_build", "dye_build", "fuse_build", "bonus_build", "blast_payoff_build", "manual_build", "fuse_payload_build", "transform_core", "transform_row", "transform_column", "cross_sweep_build"]: await board.resume_run(run)

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
				for reduced: bool in [false, true]:
					low = reduced
					for key: String in ["cross_sweep", "cross_sweep_build"]:
						await load_case(key)
						tools_panel.hide()
						for frame: int in range(45): await get_tree().process_frame
						await RenderingServer.frame_post_draw
						var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("%s_%s_%d_%d_%s.png" % [key, locale, resolution.x, theme, "low" if low else "normal"]))
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
