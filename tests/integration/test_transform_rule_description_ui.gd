extends GutTest
## Real frozen transformation offers preserve layout and read-only display.

const IDS: Array[StringName] = [&"instant_core_transform", &"instant_row_transform", &"instant_column_transform"]
const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
const BUILD: PackedScene = preload("res://ui/build_card/build_card.tscn")
var _locale: String
var _size: Vector2i
var _scale: Vector2i
var _run: RunController

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_locale = TranslationServer.get_locale()
	_size = get_window().size
	_scale = get_window().content_scale_size
	_run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1294)
	_run.initialize("fixture_dye")
	_run.state.explosion.unlocked = true
	_run.state.explosion.core_pool_unlocked = true
	_run.state.line_clear.row_unlocked = true
	assert_eq(_run.state.rule_error, "")

func after_each() -> void:
	get_tree().paused = false
	TranslationServer.set_locale(_locale)
	get_window().size = _size
	get_window().content_scale_size = _scale
	_run.retire()
	await wait_process_frames(2)

func test_three_card_offers_fit_both_languages_and_viewports_without_mutating_run() -> void:
	for size: Vector2i in [Vector2i(1024, 640), Vector2i(1280, 720)]:
		get_window().size = size
		get_window().content_scale_size = size
		for locale: String in ["en_US", "zh_CN"]:
			TranslationServer.set_locale(locale)
			for group: int in range(1):
				var choices: Array[SkillDefinition] = [_skill(IDS[0]), _skill(IDS[1]), _skill(IDS[2])]
				var offer: SkillOffer = AestheticCases.offer(_run, choices)
				var before: String = RunSnapshot.digest(RunSnapshot.capture(_run))
				var config: String = RunSnapshot.digest(RunSnapshot.config(_run))
				var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
				add_child_autofree(popup)
				popup.set_low_effects(true)
				popup.show_offer(offer)
				GameThemeUi.apply(popup, GameThemes.ALL[0])
				await wait_process_frames(8)
				var panel: Control = popup.get_node("Center/Panel") as Control
				assert_true(get_viewport().get_visible_rect().grow(1).encloses(panel.get_global_rect()), "%s %s %s" % [locale, size, panel.get_global_rect()])
				assert_true(panel.get_global_rect().encloses(popup.confirm_button.get_global_rect()))
				for child: Node in popup.options.get_children():
					var card: SkillCard = child as SkillCard
					if not card.visible: continue
					assert_eq(card.effect_label.text, SkillChoiceText.summary(card._skill, 1))
					assert_false(card.preview_label.text.is_empty())
					assert_true(card.get_global_rect().grow(1).encloses(card.action_label.get_global_rect()))
					assert_true(card.get_global_rect().grow(1).encloses(card.effect_label.get_global_rect()))
					assert_lte(card.effect_label.get_global_rect().end.y, card.preview_label.global_position.y + 1.0)
				(popup.options.get_child(0) as Button).pressed.emit()
				await wait_process_frames(2)
				assert_false(popup.confirm_button.disabled)
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(_run)), before)
				assert_eq(RunSnapshot.digest(RunSnapshot.config(_run)), config)
				if OS.get_environment("O4_TRANSFORM_CAPTURE") == "1":
					var directory: String = "res://.godot/o4-transform-captures"
					assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)
					assert_eq(get_viewport().get_texture().get_image().save_png(directory + "/%s_%d_group%d.png" % [locale, size.x, group]), OK)
				popup.queue_free()
				await wait_process_frames(2)

func _skill(id: StringName) -> SkillDefinition:
	return load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition
