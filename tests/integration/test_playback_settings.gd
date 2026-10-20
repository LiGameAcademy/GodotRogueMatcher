extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var settings: PlaybackSettings

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
	settings = game.get_node("PlaybackSettings") as PlaybackSettings
	await board.initialized
	(game.get_node("GameFeedback") as GameFeedback).set_volume(0.0)

func after_each() -> void:
	settings.close()
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_settings_restore_running_paused_and_menu_states_without_rule_changes() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var hud: Hud = game.get_node("UILayer/HUD") as Hud
	for paused: bool in [false, true]:
		get_tree().paused = paused
		hud.settings_button.grab_focus()
		hud.settings_button.pressed.emit()
		assert_true(settings.panel.visible)
		assert_true(get_tree().paused)
		assert_eq(settings.skip_button.disabled, paused)
		settings.close_button.pressed.emit()
		assert_eq(get_tree().paused, paused)
		assert_same(get_viewport().gui_get_focus_owner(), hud.settings_button)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	get_tree().paused = false
	game.call("_show_menu")
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	settings.close()
	assert_true(menu.visible)
	assert_true(get_tree().paused)
	menu.play_button.pressed.emit()
	assert_false(get_tree().paused)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)

func test_settings_keep_selected_card_and_offer_and_block_skip_without_consuming_reward() -> void:
	assert_true(board.load_explosion_demo("fixture_transform"))
	game.call("request_rewards")
	await wait_process_frames(5)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	if popup == null: return
	(popup.options.get_child(0) as Button).pressed.emit()
	var confirmation: String = popup.confirm_button.text
	var offer: SkillOffer = board.run.state.rewards.active_offer
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	(popup.get_node("%SettingsButton") as Button).pressed.emit()
	assert_true(settings.panel.visible)
	assert_true(settings.skip_button.disabled)
	assert_true(settings.menu_button.disabled)
	settings.fast_button.button_pressed = true
	settings.low_effects_button.button_pressed = true
	settings.close()
	assert_true(get_tree().paused)
	assert_same(UIManager.current_popup, popup)
	assert_same(board.run.state.rewards.active_offer, offer)
	assert_eq(popup.confirm_button.text, confirmation)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_true(game.get("preferences").fast)
	assert_true(game.get("preferences").low_effects)

func test_volume_drag_previews_changes_and_commits_once_on_release() -> void:
	watch_signals(settings)
	settings.volume_slider.drag_started.emit()
	settings.volume_slider.value = 0.25
	settings.volume_slider.value = 0.35
	assert_signal_emit_count(settings, "volume_requested", 2)
	assert_signal_not_emitted(settings, "volume_committed")
	settings.volume_slider.drag_ended.emit(true)
	assert_signal_emitted_with_parameters(settings, "volume_committed", [0.35])
	assert_signal_emit_count(settings, "volume_committed", 1)
	settings.volume_slider.value = 0.55
	assert_signal_emit_count(settings, "volume_committed", 2)

func test_loading_preferences_does_not_save_and_closing_drag_commits_once() -> void:
	watch_signals(settings)
	settings.set_volume(0.4)
	settings.set_fast(true)
	settings.set_low_effects(true)
	assert_signal_not_emitted(settings, "volume_requested")
	game.call("_open_settings")
	settings.volume_slider.drag_started.emit()
	settings.volume_slider.value = 0.6
	settings.close()
	settings.volume_slider.drag_ended.emit(true)
	assert_signal_emit_count(settings, "volume_committed", 1)
	var preferences: PlayerPreferences = game.get("preferences") as PlayerPreferences
	assert_almost_eq(preferences.volume, 0.6, 0.001)

func test_f8_inside_settings_updates_game_once_and_f1_restores_input() -> void:
	game.call("_open_settings")
	watch_signals(settings)
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F8
	settings._input(key)
	assert_signal_emit_count(settings, "fast_requested", 1)
	assert_eq(settings.fast_button.button_pressed, game.get("_fast_playback"))
	key.physical_keycode = KEY_F1
	settings._input(key)
	assert_false(settings.panel.visible)
	assert_false(get_tree().paused)

func test_settings_skip_returns_to_live_presentation_and_preserves_exact_replay() -> void:
	assert_true(board.load_explosion_demo("fixture_line_cross"))
	board._on_piece_activated(Vector2i(2, 4))
	await wait_process_frames(2)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	game.call("_open_settings")
	assert_false(settings.skip_button.disabled)
	settings.skip_button.pressed.emit()
	assert_false(settings.panel.visible)
	assert_false(get_tree().paused)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	for _frame: int in range(600):
		if board.can_selected: break
		await wait_process_frames(1)
	assert_true(board.can_selected)
	board.run.recorder.finish(board.run, "abandoned", "settings_skip_test")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.replay_file(board.run.recorder.path), replay.error)

func test_retry_closes_settings_and_initializes_new_run_without_stale_pause() -> void:
	var old_id: String = board.run.state.run_id
	game.call("_open_settings")
	await game.call("_on_retry_requested")
	assert_false(settings.panel.visible)
	assert_false(get_tree().paused)
	assert_ne(board.run.state.run_id, old_id)
	assert_true(board.can_selected)
