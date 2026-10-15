extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const EFFECT: PackedScene = preload("res://gameplay/presentation/board_signal_effect/board_signal_effect.tscn")
const CONFIG: Script = preload("res://addons/godot_core_system/source/config_system/config_manager.gd")
var game: Node2D
var board: Board
var effect: BoardSignalEffect

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
	await board.initialized
	effect = board.view.signal_effect
	game.call("_set_low_effects", false, false)
	game.call("_set_volume", 0.0, false)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_toggle_does_not_change_snapshot_geometry_or_input_surface() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var transform_before: Transform2D = board.global_transform
	var overlay_bounds: Rect2 = Rect2(effect.position, effect.size)
	for enabled: bool in [false, true, false, true]:
		game.call("_set_board_signal", enabled, false)
		assert_eq(effect.visible, enabled)
		assert_eq(board.global_transform, transform_before)
		assert_eq(Rect2(effect.position, effect.size), overlay_bounds)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_eq(overlay_bounds, board.view.get_display_rect().grow(-2.0))
	assert_eq(effect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_gt(effect.z_index, board.view.get_piece(board.rules.state.get_snapshot()[0].piece_id).z_index)
	assert_lt(effect.z_index, board.view.score_floats.z_index)

func test_pause_freezes_clock_fast_does_not_accelerate_and_low_effects_hide_it() -> void:
	await wait_process_frames(3)
	var before: float = effect.phase
	get_tree().paused = true
	await wait_process_frames(3)
	assert_eq(effect.phase, before)
	get_tree().paused = false
	effect.reset_visual()
	effect._process(1.0)
	var normal: float = effect.phase
	effect.reset_visual()
	game.call("_set_fast", true, false)
	effect._process(1.0)
	assert_eq(effect.phase, normal)
	effect.respond()
	assert_gt(effect.response, 0.0)
	game.call("_set_low_effects", true, false)
	assert_false(effect.visible)
	assert_false(effect.is_processing())
	assert_eq(effect.response, 0.0)
	game.call("_set_board_signal", false, false)
	game.call("_set_low_effects", false, false)
	assert_false(effect.visible)

func test_instance_materials_and_template_are_isolated() -> void:
	var other: BoardSignalEffect = EFFECT.instantiate() as BoardSignalEffect
	var template: ShaderMaterial = other.material as ShaderMaterial
	var initial_strength: Variant = template.get_shader_parameter("scan_strength")
	add_child_autofree(other)
	other.apply_game_theme(GameThemes.ALL[1])
	assert_ne(effect.material, other.material)
	(effect.material as ShaderMaterial).set_shader_parameter("scan_strength", 0.09)
	assert_eq((other.material as ShaderMaterial).get_shader_parameter("scan_strength"), GameThemes.ALL[1].board_signal.scan_strength)
	assert_eq(template.get_shader_parameter("scan_strength"), initial_strength)
	effect.respond()
	assert_eq(other.response, 0.0)
	assert_eq(GameThemes.ALL[0].board_signal.scan_strength, 0.018)

func test_settings_preference_round_trip_and_disabled_fallback() -> void:
	var settings: PlaybackSettings = game.get_node("PlaybackSettings") as PlaybackSettings
	game.call("_open_settings")
	settings.signal_button.button_pressed = false
	assert_false(effect.visible)
	assert_true(get_tree().paused)
	settings.close()
	assert_false(get_tree().paused)
	var preference: PlayerPreferences = game.get("preferences") as PlayerPreferences
	assert_false(preference.board_signal)
	var config: CoreSystem.ConfigManager = CONFIG.new() as CoreSystem.ConfigManager
	add_child_autofree(config)
	config.reset_config()
	assert_true(preference.save_values(config, "user://test_board_signal.cfg"))
	config.reset_config()
	assert_true(config.load_config("user://test_board_signal.cfg"))
	var loaded: PlayerPreferences = PlayerPreferences.new()
	loaded.load_values(config)
	assert_false(loaded.board_signal)
	DirAccess.remove_absolute("user://test_board_signal.cfg")

func test_real_sweep_and_retry_keep_exact_replay_and_reset_effect() -> void:
	assert_true(board.load_explosion_demo("fixture_line"))
	await board._on_piece_activated(Vector2i.ZERO)
	assert_gt(board.run.state.ledger.total, 0)
	assert_true(board.can_selected)
	assert_eq(board.director.error, "")
	board.run.recorder.finish(board.run, "abandoned", "board_signal_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(replay.run)), RunSnapshot.digest(RunSnapshot.capture(board.run)))
	effect.respond()
	assert_gt(effect.response, 0.0)
	await game.call("_on_retry_requested")
	assert_eq(effect.response, 0.0)
	assert_lt(effect.phase, 0.2)
