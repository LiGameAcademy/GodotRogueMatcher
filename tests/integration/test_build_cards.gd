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
	assert_eq(card.tooltip_text, "")
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
				assert_true(card.get_global_rect().encloses(card.effect_label.get_global_rect()))
				assert_gte(card.size.x, card.size.y, "构筑横卡宽于高: " + card.title_label.text)
	var cards: Array[PanelContainer] = []
	cards.assign(hud.build_list._cards.values())
	var first: PanelContainer = cards[0] as PanelContainer
	var second: PanelContainer = cards[1] as PanelContainer
	var first_style: StyleBoxFlat = first.get_theme_stylebox("panel") as StyleBoxFlat
	var second_style: StyleBoxFlat = second.get_theme_stylebox("panel") as StyleBoxFlat
	first_style.border_color = Color.RED
	assert_ne(first_style, second_style)
	assert_ne(second_style.border_color, Color.RED)
