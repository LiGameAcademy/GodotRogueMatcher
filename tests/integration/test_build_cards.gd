extends GutTest

const HUD: PackedScene = preload("res://ui/hud.tscn")
const CARD_SCRIPT: Script = preload("res://ui/build_card/build_card.gd")
var hud: Hud
var run: RunController
var previous_locale: String
var previous_window_size: Vector2i

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	previous_locale = TranslationServer.get_locale()
	previous_window_size = get_window().size
	TranslationServer.set_locale("zh_CN")
	hud = HUD.instantiate() as Hud
	add_child_autofree(hud)
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 864)
	run.initialize("fixture_dye")
	run.state.rewards.acquired.clear()
	run.state.skill_instances.clear()
	run.state.explosion.upgrades.clear()
	run.state.dye.upgrades.clear()
	run.state.explosion.multiplier_level = 0
	run.state.explosion.radius_level = 0
	run.state.explosion.reward_level = 0
	run.state.explosion.blast_extra_level = 0
	run.state.explosion.match_extra_level = 0
	run.state.goal_bonus_score = 0

func after_each() -> void:
	TranslationServer.set_locale(previous_locale)
	get_window().size = previous_window_size
	await wait_process_frames(2)

func test_build_lists_only_active_skills_and_keeps_level_and_remaining_refills() -> void:
	run.state.rewards.acquired[&"precision_reward"] = 2
	run.state.explosion.upgrades[&"precision_reward"] = 2
	run.state.rewards.acquired[&"instant_thin"] = 1
	run.state.rewards.acquired[&"refill_less"] = 1
	run.state.spawning.extend_refill(-1, 3)
	hud.show_run(run)
	assert_eq(hud.build_list._cards.size(), 2)
	var card: CARD_SCRIPT = hud.build_list._cards[&"precision_reward"] as CARD_SCRIPT
	assert_eq(card.level_label.text, "Lv.2")
	assert_string_contains(card.effect_label.get_parsed_text(), "额外得分+5")
	assert_string_contains(card.tooltip_text, card.title_label.text)
	assert_string_contains(card.tooltip_text, card.effect_label.get_parsed_text())
	var temporary: CARD_SCRIPT = hud.build_list._cards[&"refill_less"] as CARD_SCRIPT
	assert_eq(temporary.remaining_label.text, "剩余 3 次实际补棋")
	assert_string_contains(temporary.effect_label.text, "[b]消耗[/b]")
	assert_false(temporary.level_label.visible)
	run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)
	hud.show_run(run)
	assert_same(temporary, hud.build_list._cards[&"refill_less"])
	assert_eq(temporary.remaining_label.text, "剩余 2 次实际补棋")
	for index: int in range(2): run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)
	hud.show_run(run)
	assert_false(hud.build_list._cards.has(&"refill_less"))
	assert_string_contains(hud.history_label.text, "留白一手")

func test_build_and_formula_use_player_words_and_display_preserves_run() -> void:
	run.state.rewards.acquired[&"score_multiplier"] = 1
	run.state.explosion.multiplier_level = 1
	run.state.explosion.core_pool_unlocked = true
	run.state.ledger.commit(5, 1.2, 10, &"match", 1)
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
	hud.show_run(run)
	var summary: String = HudDetails.skills(run.state)
	for debug_text: String in ["G =", "E =", "在场", "核心补给已解锁", "下一枚生效"]:
		assert_false(summary.contains(debug_text))
	assert_string_contains(hud.score_label.tooltip_text, "基础分 × 分数倍率 + 额外得分")
	assert_string_contains(hud.score_label.tooltip_text, "总分为每笔得分的累加")
	assert_false(hud.score_label.tooltip_text.contains("B × G"))
	assert_string_contains(hud.breakdown_label.get_parsed_text(), "消除 +70")
	assert_false(hud.breakdown_label.get_parsed_text().contains("×"))
	TranslationServer.set_locale("en_US")
	hud.show_run(run)
	assert_string_contains(hud.score_label.tooltip_text, "base score × score multiplier + bonus score")
	var chinese: RegEx = RegEx.new()
	chinese.compile("[\\x{4e00}-\\x{9fff}]")
	assert_null(chinese.search(hud.score_label.tooltip_text))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)

func test_all_acquired_cards_fit_horizontal_width_and_styles_are_isolated() -> void:
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.is_persistent: run.state.rewards.acquired[skill.skill_id] = 1
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 640)]:
			get_window().size = resolution
			hud.show_run(run)
			await wait_process_frames(5)
			for panel: PanelContainer in hud.build_list._cards.values():
				var card: CARD_SCRIPT = panel as CARD_SCRIPT
				assert_lte(card.size.x, hud.build_list.size.x)
				assert_true(card.get_global_rect().encloses(card.symbol.get_global_rect()))
				assert_true(card.get_global_rect().encloses(card.badge.get_global_rect()))
				assert_false(card.effect_label.is_visible_in_tree())
				assert_string_contains(card.tooltip_text, card.effect_label.get_parsed_text())
	var cards: Array[PanelContainer] = []
	cards.assign(hud.build_list._cards.values())
	var first: PanelContainer = cards[0] as PanelContainer
	var second: PanelContainer = cards[1] as PanelContainer
	var first_style: StyleBoxFlat = first.get_theme_stylebox("panel") as StyleBoxFlat
	var second_style: StyleBoxFlat = second.get_theme_stylebox("panel") as StyleBoxFlat
	first_style.border_color = Color.RED
	assert_ne(first_style, second_style)
	assert_ne(second_style.border_color, Color.RED)

func test_manual_card_keeps_zero_uses_and_refreshes_localization_without_mutation() -> void:
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.initialize("fixture_manual_limit")
	hud.show_run(run)
	var card: CARD_SCRIPT = hud.build_list._cards[ManualActivationRules.LINE.skill_id] as CARD_SCRIPT
	assert_eq(card.remaining_label.text, "主动剩余 3 / 3 次")
	run.state.manual_uses_used[ManualActivationRules.LINE.skill_id] = 3
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
	hud.show_run(run)
	assert_same(card, hud.build_list._cards[ManualActivationRules.LINE.skill_id])
	assert_true(card.remaining_label.visible)
	assert_eq(card.remaining_label.text, "主动剩余 0 / 3 次")
	TranslationServer.set_locale("en_US")
	hud.show_run(run)
	assert_eq(card.remaining_label.text, "Manual uses left: 0 / 3")
	assert_false(card.effect_label.get_parsed_text().contains("每局"))
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)
