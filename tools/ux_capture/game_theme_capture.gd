extends Node

## Engine renders of both presets; isolated fixture, never a human balance sample.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const OUTPUT: String = "res://.godot/issue29_captures"

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
	for preset: GameTheme in GameThemes.ALL:
		game.call("_set_theme", preset.theme_id, false)
		for locale: String in ["zh_CN", "en_US"]:
			TranslationServer.set_locale(locale)
			for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
				get_window().size = size
				get_window().content_scale_size = size
				await _capture("%s_%s_%d" % [preset.theme_id, locale, size.x])
				if size.x == 1024:
					game.call("_open_settings")
					await _capture("%s_settings_%s" % [preset.theme_id, locale])
					game.get_node("PlaybackSettings").call("close")
		get_window().size = Vector2i(1280, 720)
		get_window().content_scale_size = Vector2i(1280, 720)
		TranslationServer.set_locale("zh_CN")
		var offer: SkillOffer = SkillOffer.new()
		offer.reward_id = 3
		for skill: SkillDefinition in [preload("res://gameplay/progression/content/line_clear_score.tres"), preload("res://gameplay/progression/content/line_row_span.tres"), preload("res://gameplay/progression/content/instant_core_transform.tres")]:
			offer.choices.append(skill)
			offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
		var popup: PopupSkillChoice = await UIManager.open_popup("popup_skill_choice", {"offer": offer}) as PopupSkillChoice
		(popup.options.get_child(1) as Button).pressed.emit()
		await _capture("%s_cards" % preset.theme_id)
		UIManager.close_popup()
		get_tree().paused = false
	# Presentation-only state sheet: normal/row/column/core/fuse, selection and path.
	await board.load_explosion_demo("fixture_line_cross")
	board.get_cell(Vector2i(2, 4)).piece.selected()
	board.get_cell(Vector2i(2, 4)).highlight()
	board.get_cell(Vector2i(3, 4)).highlight_path()
	for preset: GameTheme in GameThemes.ALL:
		game.call("_set_theme", preset.theme_id, false)
		await _capture("%s_special_states" % preset.theme_id)
		game.call("_set_low_effects", true, false)
		await _capture("%s_special_low" % preset.theme_id)
		game.call("_set_low_effects", false, false)
	get_tree().quit()

func _capture(name_text: String) -> void:
	for _frame: int in range(30): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(OUTPUT.path_join(name_text + ".png"))
	if error != OK: push_error(error_string(error))
