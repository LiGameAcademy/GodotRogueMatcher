extends Node

## 独立人工验收入口；禁用偏好持久化/遥测，不进入正式菜单或技能池。
const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var current_case: String = "match"
var loading: bool = false
var note: Label
var panel: VBoxContainer
var low: bool = false
var fast: bool = false
var auto_capture: bool = false
const OUTPUT: String = "res://.godot/issue128/captures_final"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auto_capture = "--capture-aesthetic" in OS.get_cmdline_user_args()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	panel = VBoxContainer.new()
	panel.position = Vector2(6, 95)
	panel.custom_minimum_size.x = 204
	layer.add_child(panel)
	note = Label.new()
	note.custom_minimum_size = Vector2(204, 160)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("352c40"))
	panel.add_child(note)
	var names: Array[String] = ["1 普通移动/匹配", "2 爆破 → 横扫", "3 横扫 → 爆破", "4 解锁L/立即匹配", "5 三类卡面/拥挤盘"]
	for index: int in range(names.size()):
		var button: Button = Button.new()
		button.text = names[index]
		button.pressed.connect(load_case.bind(AestheticCases.KEYS[index]))
		panel.add_child(button)
	_button("执行本例 / 重播先重载", play_case)
	_button("普通 / 低特效", toggle_low)
	_button("普通 / 快速", toggle_fast)
	_button("中文 / English", toggle_language)
	await load_case("match")
	if auto_capture: await capture_suite()

func _button(text: String, action: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	panel.add_child(button)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_H:
			panel.visible = not panel.visible
			get_viewport().set_input_as_handled()

func load_case(key: String) -> void:
	if loading or key not in AestheticCases.KEYS: return
	loading = true
	get_tree().paused = false
	UIManager.close_popup()
	if is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	current_case = key
	game = GAME.instantiate() as Node2D
	game.set("show_start_menu", false)
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("enable_debug_fixtures", false)
	game.set("collect_telemetry", false)
	game.set("use_external_restart", true)
	game.restart_requested.connect(load_case.bind(key))
	add_child(game)
	board = game.get_node("Board") as Board
	await board.initialized
	board.run.retire()
	board.run = AestheticCases.create(key)
	board.rules = board.run.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(board.run)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.refresh_ability_markers()
	board.can_selected = true
	game.call("_set_theme", &"light_toy", false)
	game.call("_set_fast", fast, false)
	game.call("_set_low_effects", low, false)
	game.call("_refresh_hud")
	loading = false
	_status()

func play_case() -> void:
	if loading or not board.can_selected or get_tree().paused: return
	loading = true
	if current_case in ["cards", "shape"]:
		await board.resume_run(board.run)
	elif current_case == "row_blast":
		await board._on_piece_activated(Vector2i(1, 4))
	else:
		board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
		await board.move_selected_piece(board.get_cell(Vector2i(5, 4)))
	loading = false
	_status()

func toggle_low() -> void:
	low = not low
	if is_instance_valid(game): game.call("_set_low_effects", low, false)
	_status()

func toggle_fast() -> void:
	fast = not fast
	if is_instance_valid(game): game.call("_set_fast", fast, false)
	_status()

func toggle_language() -> void:
	TranslationServer.set_locale("en_US" if TranslationServer.get_locale().begins_with("zh") else "zh_CN")

func _status() -> void:
	note.text = "#128 展示夹具，非平衡样本\n%s | %s | %s\nH隐藏/显示工具。点案例重载。\nL例请选择解锁L；三类卡可逐个重载选择。\n分数 %d | 错误 %s" % [current_case, "低特效" if low else "普通", "快速" if fast else "常速", GameManager.score, board.run.state.rule_error]

## 自动录制仅走真实行动/奖励入口；人工结论不由此生成。
func capture_suite() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for enabled: bool in [false, true]:
		low = enabled
		for key: String in AestheticCases.KEYS:
			await load_case(key)
			await _capture("%s_%s_before" % [key, str(low)])
			if key in ["shape", "cards"]:
				play_case()
				for frame: int in range(45): await get_tree().process_frame
				await _capture("%s_%s_popup" % [key, str(low)])
				if key == "shape":
					var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
					if popup != null:
						popup._select(0)
						popup.confirm_selection()
						for frame: int in range(120): await get_tree().process_frame
						await _capture("shape_%s_after" % str(low))
			else:
				play_case()
				for frame: int in range(90):
					await get_tree().process_frame
					if frame % 6 == 0: await _capture("%s_%s_%03d" % [key, str(low), frame])
			print("AESTHETIC ", key, " low=", low, " score=", GameManager.score, " error=", board.run.state.rule_error)
			# 模态尚未选择时取消整例；下一次load_case释放旧Game及其回调。
			loading = false
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		get_window().size = Vector2i(1024, 640)
		get_window().content_scale_size = Vector2i(1024, 640)
		await load_case("cards")
		play_case()
		for frame: int in range(45): await get_tree().process_frame
		await _capture("cards_%s_1024" % locale)
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		if popup != null:
			popup._select(2)
			await _capture("color_picker_%s_1024" % locale)
		loading = false
	get_tree().paused = false
	UIManager.close_popup()
	get_tree().quit()

func _capture(filename: String) -> void:
	panel.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(filename + ".png"))
	if error != OK: push_error(error_string(error))
	panel.show()
