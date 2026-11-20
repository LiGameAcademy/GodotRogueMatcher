extends Node

## 确定性UI状态证据，不提交样稿选择、不计入真人记录。
const HOST: PackedScene = preload("res://tools/aesthetic_acceptance/aesthetic_acceptance.tscn")
const OUTPUT: String = "res://.godot/issue129/captures"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var host: Node = HOST.instantiate()
	add_child(host)
	while host.board == null or host.loading: await get_tree().process_frame
	if "--review-choice" in OS.get_cmdline_user_args():
		get_window().title = "技能连珠 · 三选一预览（#129）"
		await host.load_case("cards")
		await host.play_case()
		return
	host.low = true
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = size
			get_window().content_scale_size = size
			await host.load_case("cards")
			host.panel.hide()
			await host.play_case()
			for frame: int in range(20): await get_tree().process_frame
			var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
			if popup == null:
				push_error("missing real popup")
				get_tree().quit(1)
				return
			await capture("light_toy_%s_%d_unselected" % [locale, size.x])
			for preset: GameTheme in GameThemes.ALL:
				host.game.call("_set_theme", preset.theme_id, false)
				popup._select(0)
				await capture("%s_%s_%d_selected" % [preset.theme_id, locale, size.x])
			if size.x == 1024:
				host.game.call("_set_theme", &"light_toy", false)
				var visual: SkillOffer = popup.offer.snapshot()
				var reasons: Dictionary[StringName, String] = {visual.choices[1].skill_id: "原定目标已经失效"}
				popup.set_unavailable(reasons)
				await capture("light_toy_%s_partial" % locale)
				popup.set_unavailable({})
				popup._select(2)
				await capture("light_toy_%s_color" % locale)
				popup.return_to_choices()
				for count: int in [2, 1]:
					var sheet: SkillOffer = visual.snapshot()
					sheet.choices.resize(count)
					popup.show_offer(sheet)
					popup._select(0)
					await capture("light_toy_%s_%d_choices" % [locale, count])
			get_tree().paused = false
			UIManager.close_popup()
			host.loading = false
	get_tree().quit()

func capture(filename: String) -> void:
	for frame: int in range(10): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(filename + ".png"))
	if error != OK: push_error(error_string(error))
