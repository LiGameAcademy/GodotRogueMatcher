extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
const CONFIG: Script = preload("res://addons/godot_core_system/source/config_system/config_manager.gd")
const SETTINGS_FILE: String = "user://test_feedback_settings.cfg"
var game: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	await board.initialized

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	if FileAccess.file_exists(SETTINGS_FILE): DirAccess.remove_absolute(SETTINGS_FILE)
	await wait_process_frames(2)

func test_plugin_config_round_trip_and_invalid_values_keep_safe_defaults() -> void:
	var config: CoreSystem.ConfigManager = CONFIG.new() as CoreSystem.ConfigManager
	add_child_autofree(config)
	config.reset_config()
	var preferences: PlayerPreferences = PlayerPreferences.new()
	preferences.fast = true
	preferences.low_effects = true
	preferences.volume = 0.25
	assert_true(preferences.save_values(config, SETTINGS_FILE))
	config.reset_config()
	assert_true(config.load_config(SETTINGS_FILE))
	var restored: PlayerPreferences = PlayerPreferences.new()
	restored.load_values(config)
	assert_true(restored.fast)
	assert_true(restored.low_effects)
	assert_eq(restored.volume, 0.25)
	config.set_value(PlayerPreferences.SECTION, "fast", "bad")
	config.set_value(PlayerPreferences.SECTION, "volume", "bad")
	var defaults: PlayerPreferences = PlayerPreferences.new()
	defaults.load_values(config)
	assert_false(defaults.fast)
	assert_eq(defaults.volume, 0.7)

func test_low_effects_and_fast_modes_preserve_f6_rule_snapshot() -> void:
	var baseline: String = ""
	for low: bool in [false, true]:
		game.call("_set_low_effects", low, false)
		game.call("_set_fast", low, false)
		assert_true(board.load_explosion_demo())
		board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
		assert_true(await board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01))
		var digest: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
		if not low: baseline = digest
		else: assert_eq(digest, baseline)
		assert_eq(GameManager.score, 70)
		assert_false(board.view.is_presenting())
		for cell: Cell in board.view.get_cells():
			assert_eq(cell.low_effects, low)
			if low:
				assert_false(cell.glow_border.visible)
				assert_true(cell.scan_tween == null or not cell.scan_tween.is_running())

func test_effect_toggle_during_movement_does_not_cancel_required_tween() -> void:
	var command: MovePieceCommand = RandomLegalBot.new(28).choose(board.run) as MovePieceCommand
	board.selected_piece = board.view.get_piece(command.piece_id)
	board.move_selected_piece(board.get_cell(command.target), 0.12)
	game.call("_set_low_effects", true, false)
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_eq(board.rules.state.get_piece(command.piece_id).coordinate, command.target)
	assert_true(board.can_selected)
	assert_eq(board.director.error, "")

func test_muting_cue_dedup_and_retry_stop_plugin_players() -> void:
	var feedback: GameFeedback = game.get_node("GameFeedback") as GameFeedback
	watch_signals(feedback)
	feedback.set_volume(0.0)
	feedback.play(&"match")
	assert_signal_not_emitted(feedback, "cue_played")
	feedback.set_volume(0.7)
	feedback.play(&"match")
	feedback.play(&"match")
	assert_signal_emit_count(feedback, "cue_played", 1)
	assert_gt(feedback._players.size(), 0)
	var player: AudioStreamPlayer = feedback._players.front()
	assert_true(player.playing)
	assert_true(board.load_explosion_demo())
	assert_false(player.playing)
	assert_true(feedback._players.is_empty())
	assert_true(feedback._original_modes.is_empty())

func test_finished_player_reused_by_other_caller_survives_game_cancel() -> void:
	var feedback: GameFeedback = game.get_node("GameFeedback") as GameFeedback
	feedback.play(&"reward")
	var borrowed: AudioStreamPlayer = feedback._players.front()
	assert_eq(borrowed.process_mode, Node.PROCESS_MODE_ALWAYS)
	await borrowed.finished
	assert_true(feedback._players.is_empty())
	assert_eq(borrowed.process_mode, Node.PROCESS_MODE_INHERIT)
	var external: AudioStreamPlayer = CoreSystem.audio_manager.play_sound(GameFeedback.SOUNDS[&"finish"], 0.5)
	assert_same(external, borrowed)
	feedback.cancel()
	assert_true(external.playing)
	external.stop()

func test_environment_and_particle_resources_are_instance_local() -> void:
	var other: Node2D = GAME.instantiate() as Node2D
	other.set("persist_preferences", false)
	other.set("record_runs", false)
	other.set("collect_telemetry", false)
	add_child_autofree(other)
	var other_board: Board = other.get_node("Board") as Board
	await other_board.initialized
	var environment: Environment = (game.get_node("WorldEnvironment") as WorldEnvironment).environment
	var other_environment: Environment = (other.get_node("WorldEnvironment") as WorldEnvironment).environment
	game.call("_set_low_effects", true, false)
	assert_false(environment.glow_enabled)
	assert_true(other_environment.glow_enabled)
	assert_not_same(environment, other_environment)
	var pieces: Array[PieceState] = other_board.rules.state.get_snapshot()
	var first: ChessPiece = other_board.view.get_piece(pieces[0].piece_id)
	var second: ChessPiece = other_board.view.get_piece(pieces[1].piece_id)
	assert_not_same(first.glow_particles.process_material, second.glow_particles.process_material)
