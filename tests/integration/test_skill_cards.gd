extends GutTest

const CARD: PackedScene = preload("res://ui/skill_card.tscn")
const POPUP: PackedScene = preload("res://ui/popup_skill_choice.tscn")
var previous_locale: String
var previous_window_size: Vector2i

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	previous_window_size = get_window().size

func after_each() -> void:
	get_tree().paused = false
	TranslationServer.set_locale(previous_locale)
	get_window().size = previous_window_size

func test_all_skill_descriptions_fit_card_and_popup_at_base_viewport() -> void:
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = resolution
			await wait_process_frames(3)
			await _assert_all_cards_fit()

func _assert_all_cards_fit() -> void:
	var popup: PopupSkillChoice = POPUP.instantiate() as PopupSkillChoice
	add_child_autofree(popup)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), MatchSystem.MIN_MATCH_COUNT), 864)
	for x: int in range(9):
		for y: int in range(7): run.state.rules.place_piece(Vector2i(x, y), posmod(x + y, 5))
	for offset: int in range(0, SkillOfferGenerator.CATALOG.size(), 3):
		var offer: SkillOffer = SkillOffer.new()
		for index: int in range(offset, mini(offset + 3, SkillOfferGenerator.CATALOG.size())):
			var skill: SkillDefinition = SkillOfferGenerator.CATALOG[index]
			offer.choices.append(skill)
			var target: SkillTarget = skill.choice_effect.freeze(SkillRules.effect_context(run.state), run.state.rewards.target_random) if skill.choice_effect != null else SkillTarget.new()
			target.level_before = SkillRules.level(run.state, skill)
			target.level_after = target.level_before + 1
			offer.targets[skill.skill_id] = target
		popup.show_offer(offer)
		await wait_process_frames(3)
		var panel: Control = popup.get_node("Center/Panel") as Control
		assert_true(get_viewport().get_visible_rect().grow(1.0).encloses(panel.get_global_rect()), "三选一弹窗不得超出窗口")
		for index: int in range(offer.choices.size()):
			var card: SkillCard = popup.options.get_child(index) as SkillCard
			assert_true(card.get_global_rect().encloses(card.action_label.get_global_rect()), "%s操作提示不得溢出卡片" % offer.choices[index].skill_id)
			assert_true(card.get_global_rect().encloses(card.rarity_label.get_global_rect()), "%s稀有度不得溢出卡片" % offer.choices[index].skill_id)
			assert_gte(card.effect_label.size.y, float(card.effect_label.get_minimum_size().y), "%s摘要可见" % offer.choices[index].skill_id)
			assert_eq(card.effect_label.get_parsed_text(), SkillChoiceText.summary(offer.choices[index]))
			assert_eq(card.tooltip_text, "", "整卡不重复解释完整规则")
	popup.queue_free()
	await wait_process_frames(1)

func test_legacy_definition_falls_back_and_choice_rendering_does_not_mutate_run() -> void:
	var skill: SkillDefinition = SkillDefinition.new()
	skill.description = "旧完整描述"
	assert_eq(SkillChoiceText.summary(skill), skill.description)
	var card: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(card)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 864)
	run.initialize("fixture_dye")
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var target: SkillTarget = SkillTarget.new()
	skill = preload("res://gameplay/progression/content/core_manual_detonation.tres")
	for locale: String in ["zh_CN", "en_US", "zh_CN"]:
		TranslationServer.set_locale(locale)
		card.configure(skill, target)
		assert_false(card.preview_label.visible, "持久卡不重复展示生命周期")
		assert_eq(card.tooltip_text, "")
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)
	assert_string_contains(card.effect_label.get_parsed_text(), "花1次行动")
	assert_string_contains(card.effect_label.get_parsed_text(), "空爆也消耗")

func test_frozen_refill_preview_and_consume_hint_keep_correct_lifecycle() -> void:
	var skill: SkillDefinition = preload("res://gameplay/progression/content/refill_less.tres")
	var target: SkillTarget = SkillTarget.new()
	target.value_before = 6
	target.value_after = 5
	target.remaining_before = 2
	target.remaining_after = 5
	var card: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(card)
	card.configure(skill, target)
	assert_eq(card.preview_label.text, "本次补棋：6 → 5 枚 · 余5次")
	assert_string_contains(card.effect_label.text, "[b]消耗[/b]")
	assert_eq(card.consume_label.text, "消耗")
	assert_string_contains(card.consume_label.tooltip_text, "免补棋不扣次数")
	assert_false(card.level_label.visible)
	assert_eq(card.tooltip_text, "")
	var hint: String = card.consume_label.tooltip_text
	assert_false(hint.contains("再次获得"), "术语提示不添加重复取得细则")
	assert_false(hint.contains("完整规则"))
	const TEXT_SCRIPT: Script = preload("res://ui/skill_text.gd")
	var term: TEXT_SCRIPT = card.consume_label as TEXT_SCRIPT
	var details: PanelContainer = term._make_custom_tooltip(hint) as PanelContainer
	add_child_autofree(details)
	await wait_process_frames(3)
	assert_eq((details.get_node("Rules") as Label).text, hint)
	assert_lte(details.size.x, 400.0, "术语提示折行")
	var tooltip_window: PopupPanel = PopupPanel.new()
	add_child_autofree(tooltip_window)
	var nested_details: PanelContainer = term._make_custom_tooltip(hint) as PanelContainer
	tooltip_window.add_child(nested_details)
	tooltip_window.popup()
	await wait_process_frames(4)
	assert_lte(tooltip_window.size.y, 400, "真实提示窗口先约束文字宽度，避免单字折行撑满屏幕")
	assert_eq((nested_details.get_node("Rules") as Label).text, hint)
	tooltip_window.hide()

func test_build_summary_and_config_hash_are_unchanged_by_presentation_fields() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 864, preload("res://gameplay/progression/stages/stage_config.tres"))
	run.state.rewards.acquired[&"core_manual_detonation"] = 1
	var skill: SkillDefinition = preload("res://gameplay/progression/content/core_manual_detonation.tres")
	assert_string_contains(HudDetails.skills(run.state), skill.short_description)
	assert_false(HudDetails.skills(run.state).contains("[hint="))
	# 与本片改动前同一真实截图fixture的配置哈希比较，覆盖38份运行配置。
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), "fbd0c72ec2a86c8beb73827e05b5bb2ee8aac391fdd125cd2730bdc51ff009ba")

func test_rarity_styles_are_instance_owned_and_other_card_stays_unchanged() -> void:
	var first: SkillCard = CARD.instantiate() as SkillCard
	var second: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(first)
	add_child_autofree(second)
	var target: SkillTarget = SkillTarget.new()
	first.configure(preload("res://gameplay/progression/content/blast_aftershock.tres"), target)
	second.configure(preload("res://gameplay/progression/content/core_manual_detonation.tres"), target)
	var first_style: StyleBoxFlat = first.get_theme_stylebox("normal") as StyleBoxFlat
	var second_style: StyleBoxFlat = second.get_theme_stylebox("normal") as StyleBoxFlat
	assert_ne(first_style, second_style)
	first_style.bg_color = Color.RED
	assert_ne(second_style.bg_color, Color.RED)
	assert_eq(first.rarity_label.text, "传说")
	assert_false(first.has_node("%Emblem"))
