extends GutTest

## Exercises isolated preference files and verifies the game loads them before child entry.
const FILE: String = "user://issue283_player_preferences.cfg"
const BLOCKED_FILE: String = FILE + "/blocked.cfg"
const CONFIG_PATH: String = CoreSystem.ConfigManager.SETTING_CONFIG_PATH
const GAME: PackedScene = preload("res://gameplay/game.tscn")

var _config: CoreSystem.ConfigManager
var _old_path: Variant
var _old_language: String
var _old_locale: String

func before_each() -> void:
	_old_path = ProjectSettings.get_setting(CONFIG_PATH)
	_old_language = CoreSystem.localization_manager.get_preferred_locale()
	_old_locale = TranslationServer.get_locale()
	ProjectSettings.set_setting(CONFIG_PATH, FILE)

	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value(PlayerPreferences.SECTION, "fast", true)
	legacy.set_value(PlayerPreferences.SECTION, "volume", 0.4)
	legacy.set_value("localization", "preferred_locale", "auto")
	legacy.set_value("unrelated", "keep", 42)
	assert_eq(legacy.save(FILE), OK)
	_config = CoreSystem.ConfigManager.new()
	add_child_autofree(_config)
	CoreSystem.localization_manager.configure_persistence(_config)
	assert_eq(CoreSystem.localization_manager.restore_preference(), OK)

func after_each() -> void:
	ProjectSettings.set_setting(CONFIG_PATH, _old_path)
	CoreSystem.localization_manager.configure_persistence(CoreSystem.config_manager)
	CoreSystem.localization_manager.set_preferred_locale(_old_language)
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(FILE)

func test_legacy_settings_and_language_round_trip_without_game() -> void:
	var preferences: PlayerPreferences = PlayerPreferences.new()
	preferences.load_values(_config)
	assert_true(preferences.fast)
	assert_eq(preferences.volume, 0.4)
	assert_true(preferences.board_signal)
	assert_eq(preferences.get_language_preference(), "auto")
	preferences.volume = 0.2
	assert_true(preferences.save_values(_config))

	for locale: String in ["zh_CN", "en_US", "auto"]:
		assert_eq(preferences.set_language_preference(locale, true), OK)
		assert_true(_config.load_config(FILE))
		assert_eq(CoreSystem.localization_manager.restore_preference(), OK)
		assert_eq(preferences.get_language_preference(), locale)

	var saved: ConfigFile = ConfigFile.new()
	assert_eq(saved.load(FILE), OK)
	assert_eq(saved.get_value(PlayerPreferences.SECTION, "fast"), true)
	assert_eq(saved.get_value(PlayerPreferences.SECTION, "volume"), 0.2)
	assert_eq(saved.get_value(PlayerPreferences.SECTION, "theme_id"), "light_toy")
	assert_eq(saved.get_value("unrelated", "keep"), 42)

func test_failed_writes_can_retry_and_active_language_is_kept() -> void:
	var preferences: PlayerPreferences = PlayerPreferences.new()
	preferences.load_values(_config)
	preferences.low_effects = true
	ProjectSettings.set_setting(CONFIG_PATH, BLOCKED_FILE)
	assert_false(preferences.save_values(_config))
	assert_eq(preferences.set_language_preference("zh_CN", true), ERR_FILE_CANT_WRITE)
	assert_push_error_count(2)
	assert_eq(preferences.get_language_preference(), "zh_CN")
	assert_eq(TranslationServer.get_locale(), "zh_CN")

	var saved: ConfigFile = ConfigFile.new()
	assert_eq(saved.load(FILE), OK)
	assert_false(saved.has_section_key(PlayerPreferences.SECTION, "low_effects"))
	assert_eq(saved.get_value("localization", "preferred_locale"), "auto")

	ProjectSettings.set_setting(CONFIG_PATH, FILE)
	assert_true(preferences.save_values(_config))
	assert_eq(preferences.set_language_preference("zh_CN", true), OK)
	assert_eq(saved.load(FILE), OK)
	assert_eq(saved.get_value(PlayerPreferences.SECTION, "low_effects"), true)
	assert_eq(saved.get_value("localization", "preferred_locale"), "zh_CN")

func test_game_reads_preferences_before_board_enters_tree() -> void:
	var expected: PlayerPreferences = PlayerPreferences.new()
	expected.load_values()
	var game: Node = GAME.instantiate()
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	var preferences: PlayerPreferences = game.get("preferences") as PlayerPreferences
	preferences.fast = not expected.fast
	var board: Board = game.get_node("Board") as Board
	var observed: Array[bool] = []
	board.tree_entered.connect(func() -> void: observed.append(preferences.fast))
	add_child_autofree(game)
	await board.initialized
	await wait_process_frames(1)
	assert_eq(observed, [expected.fast])
