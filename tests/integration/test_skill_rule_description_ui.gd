extends GutTest
## Real card/build scenes consume description contexts without touching gameplay state.

const CARD: PackedScene = preload("res://ui/skill_card.tscn")
const BUILD: PackedScene = preload("res://ui/build_card/build_card.tscn")
const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
var _locale: String
var _size: Vector2i
var _scale: Vector2i

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_locale = TranslationServer.get_locale()
	_size = get_window().size
	_scale = get_window().content_scale_size

func after_each() -> void:
	TranslationServer.set_locale(_locale)
	get_window().size = _size
	get_window().content_scale_size = _scale
	await wait_process_frames(2)

func test_six_long_rules_and_independent_flavor_fit_existing_popup_both_languages() -> void:
	for locale: String in ["en_US", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for size: Vector2i in [Vector2i(1024, 640), Vector2i(1280, 720)]:
			get_window().size = size
			get_window().content_scale_size = size
			for group: int in range(2):
				for count: int in [3, 2, 1]:
					var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
					add_child_autofree(popup)
					popup.set_low_effects(true)
					var offer: SkillOffer = SkillOffer.new()
					offer.offer_id = 1
					offer.reward_id = 1
					for index: int in range(count):
						var sample_index: int = index if group == 0 else 5 - index
						var skill: SkillDefinition = (load("res://gameplay/progression/content/%s.tres" % SkillRuleDescription.IDS[sample_index]) as SkillDefinition).duplicate(true) as SkillDefinition
						skill.flavor_text = "A quiet place for the next move." if locale == "en_US" else "留一点空，才有下一步。"
						offer.choices.append(skill)
						var target: SkillTarget = _display_target(skill.acquisition_effect())
						target.level_after = 1
						offer.targets[skill.skill_id] = target
					popup.show_offer(offer)
					GameThemeUi.apply(popup, GameThemes.ALL[0])
					await wait_process_frames(5)
					(popup.options.get_child(0) as SkillCard).set_selected(true)
					if count > 1: popup.set_unavailable({offer.choices[count - 1].skill_id: "原定目标已经失效"})
					await wait_process_frames(3)
					var panel: Control = popup.get_node("Center/Panel") as Control
					assert_true(get_viewport().get_visible_rect().grow(1).encloses(panel.get_global_rect()), "%s %s group%d count%d panel=%s" % [locale, size, group, count, panel.get_global_rect()])
					assert_true(panel.get_global_rect().encloses(popup.confirm_button.get_global_rect()))
					for node: Node in popup.options.get_children():
						var card: SkillCard = node as SkillCard
						if not card.visible: continue
						if locale == "en_US" and size.x == 1024 and group == 1:
							print("O4_LAYOUT count", count, " ", card.title_label.text, " content=", card.content.get_combined_minimum_size(), " effect=", card.effect_label.size, " preview=", card.preview_label.size)
						assert_true(card.get_global_rect().grow(1).encloses(card.action_label.get_global_rect()))
						assert_lte(card.effect_label.get_global_rect().end.y, card.flavor_label.global_position.y + 1.0)
						assert_false(card.effect_label.text.contains("rules."))
					if count == 3 and OS.get_environment("O4_RULE_CAPTURE") == "1":
						var path: String = "res://.godot/o4-description-captures"
						assert_eq(DirAccess.make_dir_recursive_absolute(path), OK)
						var image: Image = get_viewport().get_texture().get_image()
						assert_eq(image.save_png(path + "/%s_%d_group%d.png" % [locale, size.x, group]), OK)
					(popup.options.get_child(0) as Button).pressed.emit()
					if offer.choices[0].requires_color_choice(): popup.picker.select_color(0)
					assert_false(popup.confirm_button.disabled)
					var submitted: Array[int] = [0]
					popup.skill_selected.connect(func(_id: int, _skill: StringName) -> void: submitted[0] += 1)
					popup.color_skill_selected.connect(func(_id: int, _skill: StringName, _color: int) -> void: submitted[0] += 1)
					await wait_process_frames(3)
					_click(popup.confirm_button)
					await wait_process_frames(2)
					assert_eq(submitted[0], 1, "shared confirmation remains usable")
					popup.queue_free()
					await wait_process_frames(2)

func test_owned_and_candidate_contexts_keep_mixed_lifetimes_and_config_catalog_default() -> void:
	TranslationServer.set_locale("en_US")
	var skill: SkillDefinition = load("res://gameplay/progression/content/composite_refill_color.tres") as SkillDefinition
	var card: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(card)
	var target: SkillTarget = SkillTarget.new()
	target.level_after = 1
	card.configure(skill, target)
	assert_false(card.consume_label.visible, "mixed card is not consumed as a whole")
	assert_string_contains(card.effect_label.text, "3 actual refills")
	var build: PanelContainer = BUILD.instantiate() as PanelContainer
	add_child_autofree(build)
	build.call("configure", skill, 1, 0)
	assert_string_contains(str(build.get("effect_label").text), "0 actual refills remaining")
	assert_string_contains(str(build.get("effect_label").text), "persists after")
	assert_string_contains(str(build.get("remaining_label").text), "Refill modifier")
	var multiplier: SkillDefinition = load("res://gameplay/progression/content/score_multiplier.tres") as SkillDefinition
	build.call("configure", multiplier, 3, -1)
	assert_string_contains(str(build.get("effect_label").text), "0.6")
	assert_string_contains(SkillChoiceText.summary(multiplier), "Add 0.2")

func test_default_popup_insets_also_fit_three_cards_without_a_game_theme() -> void:
	TranslationServer.set_locale("en_US")
	get_window().size = Vector2i(1024, 640)
	get_window().content_scale_size = Vector2i(1024, 640)
	var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
	add_child_autofree(popup)
	popup.set_low_effects(true)
	var offer: SkillOffer = SkillOffer.new()
	for id: String in ["composite_clear_dye", "composite_refill_color", "goal_score_bonus"]:
		var skill: SkillDefinition = load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition
		offer.choices.append(skill)
		var target: SkillTarget = _display_target(skill.acquisition_effect())
		target.level_after = 1
		offer.targets[skill.skill_id] = target
	popup.show_offer(offer)
	await wait_process_frames(8)
	var panel: Control = popup.get_node("Center/Panel") as Control
	assert_true(get_viewport().get_visible_rect().grow(1).encloses(panel.get_global_rect()), str(panel.get_global_rect()))
	for node: Node in popup.options.get_children():
		var card: SkillCard = node as SkillCard
		assert_true(card.get_global_rect().grow(1).encloses(card.action_label.get_global_rect()))

func _display_target(effect: SkillEffect) -> SkillTarget:
	if effect is CompositeEffect:
		var composite: CompositeSkillTarget = CompositeSkillTarget.new()
		for child: SkillEffect in (effect as CompositeEffect).children:
			composite.leaf_targets.append(_display_target(child))
		return composite
	var target: SkillTarget = SkillTarget.new()
	if effect is RefillCountEffect:
		target.value_before = 3
		target.value_after = 2
		target.remaining_after = (effect as RefillCountEffect).batches
	elif effect is ColorWeightEffect:
		target.color = 0
		target.value_before = 4
		target.value_after = 4 + (effect as ColorWeightEffect).delta
	elif effect is DyeMaterialEffect:
		target.deferred = true
	elif effect is ClearMaterialEffect:
		target.color_groups = [PackedInt64Array([10])]
		target.fuse_counts = [1]
	elif effect is DemolitionStatEffect or effect is InstallLineUpgradeEffect:
		target.value_after = 1
	elif effect is InstallGoalBonusEffect:
		target.value_after = (effect as InstallGoalBonusEffect).bonus_score
	return target

func _click(button: Button) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	get_viewport().push_input(press, true)
	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)

