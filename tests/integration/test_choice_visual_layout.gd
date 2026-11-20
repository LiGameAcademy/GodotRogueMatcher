extends GutTest

const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
var old_locale: String
var old_size: Vector2i
var old_scale: Vector2i

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	old_locale = TranslationServer.get_locale()
	old_size = get_window().size
	old_scale = get_window().content_scale_size

func after_each() -> void:
	get_tree().paused = false
	TranslationServer.set_locale(old_locale)
	get_window().size = old_size
	get_window().content_scale_size = old_scale
	await wait_process_frames(2)

func _popup(run: RunController, count: int, preset: GameTheme) -> PopupSkillChoice:
	var offer: SkillOffer = run.state.rewards.active_offer
	offer.choices.resize(count)
	var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
	add_child(popup)
	popup.set_low_effects(true)
	popup.show_offer(offer)
	GameThemeUi.apply(popup, preset)
	return popup

func test_three_two_one_choices_both_themes_languages_and_viewports_fit_without_rule_changes() -> void:
	for preset: GameTheme in GameThemes.ALL:
		for locale: String in ["zh_CN", "en_US"]:
			TranslationServer.set_locale(locale)
			for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
				get_window().size = size
				get_window().content_scale_size = size
				for count: int in [3, 2, 1]:
					var run: RunController = AestheticCases.create("cards")
					var popup: PopupSkillChoice = _popup(run, count, preset)
					var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
					await wait_process_frames(6)
					var panel: Control = popup.get_node("Center/Panel") as Control
					var tools: Control = popup.view_button.get_parent() as Control
					assert_true(get_viewport().get_visible_rect().grow(1).encloses(panel.get_global_rect()), "%s %s %s" % [preset.theme_id, locale, size])
					assert_eq(popup.options.get_children().filter(func(card: Node) -> bool: return (card as Control).visible).size(), count)
					assert_almost_eq(tools.get_global_rect().position.y, popup.view_button.get_global_rect().position.y, 1.0)
					assert_lte(tools.size.y, 42.0)
					if locale == "en_US": assert_eq(popup.view_button.tr(popup.view_button.text), "View board")
					assert_true(panel.get_global_rect().encloses(popup.confirm_button.get_global_rect()))
					for index: int in range(count):
						var card: SkillCard = popup.options.get_child(index) as SkillCard
						assert_true(card.get_global_rect().grow(1).encloses(card.action_label.get_global_rect()))
						assert_true(card.get_global_rect().grow(1).encloses(card.effect_label.get_global_rect()))
						if card.preview_label.visible:
							assert_gte(card.preview_label.global_position.y, card.effect_label.get_global_rect().end.y - 1.0)
							assert_lte(card.preview_label.get_global_rect().end.y, card.flavor_label.global_position.y + 1.0)
					popup._select(0)
					popup.toggle_board_view()
					popup.toggle_board_view()
					assert_string_contains((popup.options.get_child(0) as SkillCard).action_label.text, "✓")
					assert_false(popup.confirm_button.disabled)
					assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
					popup.queue_free()
					await wait_process_frames(2)

func test_selected_and_unavailable_state_survives_locale_and_theme_changes() -> void:
	var run: RunController = AestheticCases.create("cards")
	var popup: PopupSkillChoice = _popup(run, 3, GameThemes.ALL[0])
	popup._select(0)
	var reasons: Dictionary[StringName, String] = {AestheticCases.CARDS[2].skill_id: "原定目标已经失效"}
	popup.set_unavailable(reasons)
	var selected: SkillCard = popup.options.get_child(0) as SkillCard
	var unavailable: SkillCard = popup.options.get_child(2) as SkillCard
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	for locale: String in ["en_US", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for preset: GameTheme in GameThemes.ALL:
			GameThemeUi.apply(popup, preset)
			await wait_process_frames(10)
			assert_true(selected._selected)
			assert_string_contains(selected.action_label.text, "✓")
			assert_true(unavailable.disabled)
			assert_string_contains(unavailable.action_label.text, tr("原定目标已经失效"))
			assert_eq(unavailable.content.modulate, Color.WHITE)
			assert_true(unavailable.get_global_rect().grow(1).encloses(unavailable.action_label.get_global_rect()))
			popup._select(2)
			assert_true(selected._selected)
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	popup.queue_free()
	await wait_process_frames(2)

func test_deselect_restores_surface_and_other_card_style_is_unchanged() -> void:
	var run: RunController = AestheticCases.create("cards")
	var popup: PopupSkillChoice = _popup(run, 3, GameThemes.ALL[0])
	var first: SkillCard = popup.options.get_child(0) as SkillCard
	var second: SkillCard = popup.options.get_child(1) as SkillCard
	var original: Color = (second.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	popup._select(0)
	assert_ne((first.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, original)
	popup._select(1)
	assert_eq((first.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, original)
	assert_ne((second.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, original)
	popup.queue_free()
	await wait_process_frames(2)
