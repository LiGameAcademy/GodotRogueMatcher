extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const VIEW: PackedScene = preload("res://gameplay/board/board_view.tscn")
const CONFIG: Script = preload("res://addons/godot_core_system/source/config_system/config_manager.gd")
var game: Node2D
var board: Board
var previous_locale: String

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	previous_locale = TranslationServer.get_locale()
	get_tree().paused = false
	UIManager.close_popup()
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	await board.initialized
	await wait_process_frames(2)
	(game.get_node("GameFeedback") as GameFeedback).set_volume(0.0)

func after_each() -> void:
	(game.get_node("PlaybackSettings") as PlaybackSettings).close()
	get_tree().paused = false
	UIManager.close_popup()
	TranslationServer.set_locale(previous_locale)
	await wait_process_frames(2)

func test_presets_and_saved_preference_round_trip_and_invalid_value_fallback() -> void:
	for preset: GameTheme in GameThemes.ALL: assert_eq(preset.validation_error(), "")
	assert_eq(GameThemes.find(&"unknown").theme_id, &"light_toy")
	var config: CoreSystem.ConfigManager = CONFIG.new() as CoreSystem.ConfigManager
	add_child_autofree(config)
	config.reset_config()
	var preference: PlayerPreferences = PlayerPreferences.new()
	preference.theme_id = &"dark_instrument"
	assert_true(preference.save_values(config, "user://test_game_theme.cfg"))
	config.reset_config()
	assert_true(config.load_config("user://test_game_theme.cfg"))
	var restored: PlayerPreferences = PlayerPreferences.new()
	restored.load_values(config)
	assert_eq(restored.theme_id, &"dark_instrument")
	config.set_value(PlayerPreferences.SECTION, "theme_id", "missing")
	restored.load_values(config)
	assert_eq(restored.theme_id, &"light_toy")
	DirAccess.remove_absolute("user://test_game_theme.cfg")

func test_switching_in_settings_preserves_pause_focus_rules_and_random_streams() -> void:
	var settings: PlaybackSettings = game.get_node("PlaybackSettings") as PlaybackSettings
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var config: String = RunSnapshot.digest(RunSnapshot.config(board.run))
	game.call("_open_settings")
	var focus: Control = get_viewport().gui_get_focus_owner()
	for index: int in [1, 0, 1]:
		settings.theme_choice.select(index)
		settings.theme_choice.item_selected.emit(index)
		assert_same(game.get("game_theme"), GameThemes.ALL[index])
		var background: ColorRect = game.get_node("ColorRect") as ColorRect
		assert_eq(background.color, GameThemes.ALL[index].background)
		assert_eq(background.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_true(get_tree().paused)
		assert_same(get_viewport().gui_get_focus_owner(), focus)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
		assert_eq(RunSnapshot.digest(RunSnapshot.config(board.run)), config)
	TranslationServer.set_locale("en_US")
	assert_eq(settings.theme_choice.get_item_text(1), "Dark Instrument")
	assert_eq(settings.theme_choice.selected, 1)
	settings.close()
	assert_false(get_tree().paused)

func test_switching_retains_offer_selected_card_and_confirmation() -> void:
	assert_true(board.load_explosion_demo("fixture_transform"))
	LevelUpSystem.resolve_pending_rewards(board)
	await wait_process_frames(5)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	if popup == null: return
	(popup.options.get_child(1) as Button).pressed.emit()
	var card: SkillCard = popup.options.get_child(1) as SkillCard
	var offer: SkillOffer = popup.offer
	var text: String = popup.confirm_button.text
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	for preset: GameTheme in GameThemes.ALL:
		game.call("_set_theme", preset.theme_id, false)
		assert_same(popup.offer, offer)
		assert_true(card.get("_selected"))
		assert_eq(popup.confirm_button.text, text)
		assert_eq(card.get_theme_stylebox("normal").get("bg_color"), preset.ui_theme.get_color("surface", "Game"))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
		assert_true(get_tree().paused)

func test_shader_instances_and_templates_stay_isolated_across_views() -> void:
	var a: BoardView = VIEW.instantiate() as BoardView
	var b: BoardView = VIEW.instantiate() as BoardView
	add_child_autofree(a)
	add_child_autofree(b)
	for view: BoardView in [a, b]:
		view.configure(2, 2, Vector2(64, 64), Vector2.ONE)
		var rules: BoardRules = BoardRules.new(BoardState.new(2, 2), 5)
		rules.place_piece(Vector2i.ZERO, 2)
		view.rebuild(rules.state.get_snapshot())
	a.apply_game_theme(GameThemes.ALL[0])
	b.apply_game_theme(GameThemes.ALL[1])
	var first: ShaderMaterial = a.get_piece(1).polygon.material as ShaderMaterial
	var second: ShaderMaterial = b.get_piece(1).polygon.material as ShaderMaterial
	assert_ne(first, second)
	var initial_flash: Variant = second.get_shader_parameter("flash")
	first.set_shader_parameter("flash", 1.0)
	assert_eq(second.get_shader_parameter("flash"), initial_flash)
	assert_eq(a.get_piece(1).polygon.color, GameThemes.ALL[0].board.piece_colors[2])
	assert_eq(b.get_piece(1).polygon.color, GameThemes.ALL[1].board.piece_colors[2])
	var cell_a: ShaderMaterial = a.get_cell(Vector2i.ZERO).background.material as ShaderMaterial
	var cell_b: ShaderMaterial = b.get_cell(Vector2i.ZERO).background.material as ShaderMaterial
	cell_a.set_shader_parameter("rounding", 0.15)
	assert_ne(cell_b.get_shader_parameter("rounding"), 0.15)
	assert_eq(GameThemes.ALL[0].board.cell_rounding, 0.085)

func test_switch_during_real_move_keeps_barrier_and_exact_file_replay() -> void:
	assert_true(board.load_explosion_demo())
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.20)
	await wait_process_frames(2)
	game.call("_set_theme", &"dark_instrument", false)
	game.call("_set_low_effects", true, false)
	game.call("_set_theme", &"light_toy", false)
	for _frame: int in range(600):
		if board.can_selected: break
		await wait_process_frames(1)
	assert_true(board.can_selected)
	assert_eq(board.director.error, "")
	assert_eq(GameManager.score, 70)
	board.run.recorder.finish(board.run, "abandoned", "theme_switch_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_retry_and_new_catalog_cards_inherit_theme_without_resetting_filters() -> void:
	game.call("_set_theme", &"dark_instrument", false)
	await game.call("_on_retry_requested")
	for piece: PieceState in board.rules.state.get_snapshot():
		assert_eq(board.view.get_piece(piece.piece_id).polygon.color, GameThemes.ALL[1].board.piece_colors[piece.match_color])
	var pool: SkillPool = game.get_node("SkillPool") as SkillPool
	pool.open(board.run)
	pool.rarity_filter.select(2)
	pool.rarity_filter.item_selected.emit(2)
	var count: int = pool.entries.get_child_count()
	game.call("_set_theme", &"light_toy", false)
	assert_eq(pool.rarity_filter.selected, 2)
	assert_eq(pool.entries.get_child_count(), count)
	assert_true(get_tree().paused)
	for child: Node in pool.entries.get_children():
		var card: SkillCard = child as SkillCard
		assert_eq((card.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, GameThemes.ALL[0].ui_theme.get_color("surface", "Game"))
	pool.close()
