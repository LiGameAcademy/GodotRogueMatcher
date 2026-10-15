extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const BACKGROUND: PackedScene = preload("res://gameplay/presentation/game_background/game_background.tscn")
const CONFIG: Script = preload("res://addons/godot_core_system/source/config_system/config_manager.gd")
var game: Node2D
var board: Board
var background: GameBackground

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("show_start_menu", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	background = game.get_node("ColorRect") as GameBackground
	await board.initialized
	await wait_process_frames(2)
	game.call("_set_volume", 0.0, false)
	game.call("_set_low_effects", false, false)
	game.call("_set_background_motion", true, false)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_settings_save_and_invalid_value_falls_back_to_default() -> void:
	var config: CoreSystem.ConfigManager = CONFIG.new() as CoreSystem.ConfigManager
	add_child_autofree(config)
	config.reset_config()
	var preference: PlayerPreferences = PlayerPreferences.new()
	preference.background_motion = false
	assert_true(preference.save_values(config, "user://test_background.cfg"))
	config.reset_config()
	assert_true(config.load_config("user://test_background.cfg"))
	var restored: PlayerPreferences = PlayerPreferences.new()
	restored.load_values(config)
	assert_false(restored.background_motion)
	config.set_value(PlayerPreferences.SECTION, "background_motion", "invalid")
	var defaults: PlayerPreferences = PlayerPreferences.new()
	defaults.load_values(config)
	assert_true(defaults.background_motion)
	DirAccess.remove_absolute("user://test_background.cfg")

func test_clock_freezes_on_pause_and_fast_playback_does_not_multiply_it() -> void:
	var before: float = background.phase
	await wait_process_frames(4)
	assert_gt(background.phase, before)
	get_tree().paused = true
	before = background.phase
	await wait_process_frames(4)
	assert_eq(background.phase, before)
	get_tree().paused = false
	background.reset_visual()
	background._process(1.0)
	var normal: float = background.phase
	background.reset_visual()
	game.call("_set_fast", true, false)
	background._process(1.0)
	assert_eq(background.phase, normal)

func test_disabled_and_reduced_effects_use_solid_background_and_keep_rule_state() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	background.respond_to_score(500)
	assert_gt(background.response, 0.0)
	game.call("_set_low_effects", true, false)
	assert_null(background.material)
	assert_false(background.is_processing())
	assert_eq(background.response, 0.0)
	background.respond_to_score(500)
	assert_eq(background.response, 0.0)
	game.call("_set_background_motion", false, false)
	game.call("_set_low_effects", false, false)
	assert_null(background.material)
	game.call("_set_background_motion", true, false)
	assert_true(background.material is ShaderMaterial)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)

func test_materials_and_shared_presets_are_not_mutated_by_other_instances() -> void:
	var other: GameBackground = BACKGROUND.instantiate() as GameBackground
	add_child_autofree(other)
	other.apply_game_theme(GameThemes.ALL[0])
	var a: ShaderMaterial = background.material as ShaderMaterial
	var b: ShaderMaterial = other.material as ShaderMaterial
	assert_ne(a, b)
	background.respond_to_score(100000)
	assert_eq(background.response, GameThemes.ALL[0].background_flow.score_response)
	assert_eq(other.response, 0.0)
	assert_eq(b.get_shader_parameter("response"), 0.0)
	assert_eq(GameThemes.ALL[0].background_flow.contrast, 0.045)
	var fresh: GameBackground = BACKGROUND.instantiate() as GameBackground
	var original_strength: Variant = (fresh.material as ShaderMaterial).get_shader_parameter("strength")
	a.set_shader_parameter("strength", 0.8)
	assert_eq((fresh.material as ShaderMaterial).get_shader_parameter("strength"), original_strength)
	assert_eq(b.get_shader_parameter("strength"), 0.045)
	# A fresh scene still starts from the resource's original shader values.
	add_child_autofree(fresh)
	fresh.apply_game_theme(GameThemes.ALL[0])
	assert_eq((fresh.material as ShaderMaterial).get_shader_parameter("strength"), 0.045)

func test_real_score_and_retry_are_visual_only_and_replay_stays_exact() -> void:
	assert_true(board.load_explosion_demo())
	var responses: Array[float] = []
	board.view.score_floats.score_visualized.connect(func(_entry: ScoreEntry, _origin: Vector2) -> void: responses.append(background.response))
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01))
	assert_eq(GameManager.score, 70)
	assert_false(responses.is_empty())
	for response_value: float in responses: assert_gt(response_value, 0.0)
	board.run.recorder.finish(board.run, "abandoned", "background_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(board.run)))
	background.phase = 20.0
	await game.call("_on_retry_requested")
	assert_lt(background.phase, 1.0)
	assert_eq(background.response, 0.0)

func test_settings_toggle_preserves_pause_and_rules() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var settings: PlaybackSettings = game.get_node("PlaybackSettings") as PlaybackSettings
	game.call("_open_settings")
	settings.background_button.button_pressed = false
	assert_true(get_tree().paused)
	assert_null(background.material)
	assert_false((game.get("preferences") as PlayerPreferences).background_motion)
	settings.close()
	assert_false(get_tree().paused)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
