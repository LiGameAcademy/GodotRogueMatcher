extends GutTest
## Real frozen offers, build cards and pool contexts display the same score contribution.

const IDS: Array[StringName] = [&"match_extra", &"blast_extra", &"blast_reward", &"line_clear_score"]
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

func test_definition_current_proposed_and_max_contexts_use_real_acquisitions() -> void:
	for id: StringName in IDS:
		var skill: SkillDefinition = _skill(id)
		TranslationServer.set_locale("en_US")
		assert_string_contains(SkillPoolText.rule_view(_run, skill).context, "Definition only")
		AestheticCases.install(_run, skill)
		assert_eq(_run.state.rule_error, "")
		assert_eq(SkillRules.level(_run.state, skill), 1)
		for locale: String in ["en_US", "zh_CN"]:
			TranslationServer.set_locale(locale)
			var build: PanelContainer = BUILD.instantiate() as PanelContainer
			add_child_autofree(build)
			build.call("configure", skill, 1, -1)
			assert_eq(str(build.get("effect_label").text), SkillChoiceText.summary(skill, 1, -1, true))
			assert_eq(SkillPoolText.rule_view(_run, skill).text, str(build.get("effect_label").text))
			var target: SkillTarget = SkillRules.freeze_target(_run.state, skill)
			assert_eq(target.level_before, 1)
			assert_eq(target.level_after, 2)
			assert_ne(SkillChoiceText.summary(skill, target.level_after), str(build.get("effect_label").text))
		if skill.maximum_level > 0:
			for level: int in range(1, skill.maximum_level): AestheticCases.install(_run, skill)
			assert_eq(_run.state.rule_error, "")
			assert_eq(SkillRules.level(_run.state, skill), skill.maximum_level)
			assert_false(SkillPoolText.rule_view(_run, skill).text.contains("Manual rule"))

func test_three_card_offers_fit_both_languages_and_viewports_without_mutating_run() -> void:
	for id: StringName in IDS:
		AestheticCases.install(_run, _skill(id))
		assert_eq(_run.state.rule_error, "")
	for size: Vector2i in [Vector2i(1024, 640), Vector2i(1280, 720)]:
		get_window().size = size
		get_window().content_scale_size = size
		for locale: String in ["en_US", "zh_CN"]:
			TranslationServer.set_locale(locale)
			for group: int in range(2):
				var choices: Array[SkillDefinition] = [_skill(IDS[group * 3]), _skill(&"blast_extra"), _skill(&"blast_reward")]
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
					assert_eq(card.effect_label.text, SkillChoiceText.summary(card._skill, 2))
					assert_false(card.preview_label.text.is_empty())
					assert_true(card.get_global_rect().grow(1).encloses(card.action_label.get_global_rect()))
					assert_true(card.get_global_rect().grow(1).encloses(card.effect_label.get_global_rect()))
					assert_lte(card.effect_label.get_global_rect().end.y, card.preview_label.global_position.y + 1.0)
				(popup.options.get_child(0) as Button).pressed.emit()
				await wait_process_frames(2)
				assert_false(popup.confirm_button.disabled)
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(_run)), before)
				assert_eq(RunSnapshot.digest(RunSnapshot.config(_run)), config)
				if OS.get_environment("O4_SCORE_CAPTURE") == "1":
					var directory: String = "res://.godot/o4-score-captures"
					assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)
					assert_eq(get_viewport().get_texture().get_image().save_png(directory + "/%s_%d_group%d.png" % [locale, size.x, group]), OK)
				popup.queue_free()
				await wait_process_frames(2)

func _skill(id: StringName) -> SkillDefinition:
	return load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition
