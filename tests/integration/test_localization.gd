extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var previous_locale: String
var previous_preference: String

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	previous_locale = TranslationServer.get_locale()
	previous_preference = CoreSystem.localization_manager.get_preferred_locale()
	get_tree().paused = false
	TranslationServer.set_locale("zh_CN")
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	await board.initialized
	await wait_process_frames(2)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	CoreSystem.localization_manager.set_preferred_locale(previous_preference)
	TranslationServer.set_locale(previous_locale)

func test_first_language_switch_refreshes_unopened_tutorial_and_preserves_run() -> void:
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	menu.open(false, false, false)
	assert_null(menu.tutorial.session.run)
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_eq(CoreSystem.localization_manager.set_preferred_locale("en_US"), OK)
	await wait_process_frames(1)
	assert_true(menu.version_label.text.contains("Desktop playtest"))
	assert_eq(menu.play_button.text, "Play")
	var hud: Hud = game.get_node("UILayer/HUD") as Hud
	assert_eq(hud.score_label.text, "Score  0")
	assert_true(hud.goal_progress.target_label.tooltip_text.contains("Stage"))
	assert_eq(menu.mode_button.get_item_text(1), "Stage challenge")
	assert_string_contains(menu.mode_hint.text, "Refills grow")
	assert_string_contains(hud.spawn_preview.tooltip_text, "Next refill 3 pieces")
	assert_eq(snapshot, RunSnapshot.digest(RunSnapshot.capture(board.run)))
	assert_null(menu.tutorial.session.run)
	assert_eq(CoreSystem.localization_manager.set_preferred_locale("zh_CN"), OK)
	assert_eq(menu.play_button.text, "开始试玩")
	assert_eq(hud.score_label.text, "分数  0")

func test_every_skill_has_english_text_without_mutating_resources() -> void:
	TranslationServer.set_locale("en_US")
	assert_eq(SkillOfferGenerator.CATALOG.size(), 38)
	var chinese: RegEx = RegEx.new()
	chinese.compile("[\\x{4e00}-\\x{9fff}]")
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var title: String = skill.title
		var description: String = skill.description
		assert_null(chinese.search(String(TranslationServer.translate(title))), skill.skill_id)
		assert_null(chinese.search(String(TranslationServer.translate(description))), skill.skill_id)
		assert_eq(skill.title, title)
		assert_eq(skill.description, description)

func test_color_picker_switch_preserves_selected_target_and_board_view() -> void:
	var popup: PopupSkillChoice = preload("res://ui/popup_skill_choice.tscn").instantiate() as PopupSkillChoice
	add_child_autofree(popup)
	board.load_explosion_demo()
	var skill: SkillDefinition = preload("res://gameplay/progression/content/instant_color_clear.tres")
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = 12
	offer.reward_id = 4
	offer.choices = [skill]
	offer.targets[skill.skill_id] = skill.choice_effect.freeze(SkillRules.effect_context(board.run.state), board.run.state.rewards.target_random)
	popup.show_offer(offer)
	popup._select(0)
	var chosen: int = -1
	for color: int in range(5):
		if not (popup.picker.colors.get_child(color) as Button).disabled:
			chosen = color
			break
	assert_gte(chosen, 0)
	popup.picker.select_color(chosen)
	popup.toggle_board_view()
	TranslationServer.set_locale("en_US")
	await wait_process_frames(1)
	assert_eq(popup.picker.selected_color, chosen)
	assert_true(popup.viewing_board)
	assert_eq(popup.offer.offer_id, 12)
	assert_true(popup.return_label.text.contains("view-only"))
	assert_true(popup.heading.text.contains("Choose a color"))
	assert_true((popup.picker.colors.get_child(chosen) as Button).text.begins_with("✓ Selected"))
	assert_false(popup._submitted)
	TranslationServer.set_locale("zh_CN")
	await wait_process_frames(1)
	assert_eq(popup.picker.selected_color, chosen)
	assert_true(popup.viewing_board)
	assert_true((popup.picker.colors.get_child(chosen) as Button).text.begins_with("✓ 已选"))
