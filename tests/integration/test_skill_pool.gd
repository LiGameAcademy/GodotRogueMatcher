extends GutTest

const POOL: PackedScene = preload("res://ui/skill_pool/skill_pool.tscn")
const GAME: PackedScene = preload("res://gameplay/game.tscn")
var pool: SkillPool
var run: RunController
var previous_locale: String

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 42)
	run.initialize("fixture_dye")
	pool = POOL.instantiate() as SkillPool
	add_child_autofree(pool)

func after_each() -> void:
	pool.close()
	get_tree().paused = false
	TranslationServer.set_locale(previous_locale)
	UIManager.close_popup()
	await wait_process_frames(2)

func test_browsing_and_locale_changes_preserve_snapshot_offer_and_random_streams() -> void:
	run.enter_rewards()
	run.state.pending_rewards = 1
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var offer: SkillOffer = generator.generate(run)
	var original: String = RunSnapshot.digest(RunSnapshot.capture(run))
	pool.open(run)
	assert_eq(pool.entries.get_child_count(), SkillOfferGenerator.CATALOG.size())
	TranslationServer.set_locale("en_US")
	pool.close()
	assert_same(run.state.rewards.active_offer, offer)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), original)
	assert_false(get_tree().paused)

func test_escape_restores_existing_pause_and_does_not_reach_game_shortcuts() -> void:
	get_tree().paused = true
	pool.open(run)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	pool._input(key)
	assert_false(pool.panel.visible)
	assert_true(get_tree().paused)

func test_catalog_uses_short_effects_and_actual_prerequisite_titles() -> void:
	var found: bool = false
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var text: String = SkillPoolText.details(run, skill)
		assert_false(text.contains("E+"))
		assert_false(text.contains("权重必须"))
		if skill.skill_id == &"relay_capacity":
			found = true
			for parent: SkillDefinition in SkillOfferGenerator.CATALOG:
				if parent.skill_id == skill.prerequisite: assert_true(text.contains(tr(parent.title)))
	assert_true(found)

func test_choice_menu_roundtrip_preserves_popup_and_observation_location() -> void:
	var game: Node2D = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("show_start_menu", false)
	add_child_autofree(game)
	var board: Board = game.get_node("Board") as Board
	await board.initialized
	board.run.enter_rewards()
	board.run.state.pending_rewards = 1
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var offer: SkillOffer = generator.generate(board.run)
	var popup: PopupSkillChoice = await UIManager.open_popup("popup_skill_choice", {"offer": offer}) as PopupSkillChoice
	var collection: RunCollection = game.get_node("RunCollection") as RunCollection
	collection.location("skill_choice")
	popup.skill_pool_requested.emit()
	var game_pool: SkillPool = game.get_node("SkillPool") as SkillPool
	assert_true(game_pool.panel.visible)
	assert_eq(collection.ui, "skill_pool")
	game_pool.close()
	assert_eq(collection.ui, "skill_choice")
	assert_true(get_tree().paused)
	assert_same(UIManager.current_popup, popup)
	assert_same(popup.offer, offer)

func test_terminal_and_presentation_views_restore_their_previous_state() -> void:
	for phase: RunState.Phase in [RunState.Phase.INPUT, RunState.Phase.REWARDS, RunState.Phase.ERROR]:
		run.state.phase = phase
		run.state.is_game_over = phase == RunState.Phase.ERROR
		var original: String = RunSnapshot.digest(RunSnapshot.capture(run))
		pool.open(run)
		pool.close()
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), original)
		assert_false(get_tree().paused)
