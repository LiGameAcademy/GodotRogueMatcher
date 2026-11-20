extends GutTest

## Verifies visual transitions cannot delay modal ownership or mutate run state.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
const SETTINGS: PackedScene = preload("res://ui/playback_settings/playback_settings.tscn")
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

func test_button_feedback_preserves_hit_rect_and_never_dispatches_an_action() -> void:
	var button: Button = (game.get_node("UILayer/HUD") as Hud).settings_button
	var bounds: Rect2 = button.get_global_rect()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	watch_signals(button)
	button.mouse_entered.emit()
	await wait_seconds(0.2)
	assert_ne(button.self_modulate, Color.WHITE)
	assert_eq(button.get_global_rect(), bounds)
	button.button_down.emit()
	await wait_seconds(0.2)
	assert_lt(button.self_modulate.r, 1.0)
	button.disabled = true
	await wait_seconds(0.2)
	assert_eq(button.self_modulate, Color.WHITE)
	button.disabled = false
	button.button_up.emit()
	button.mouse_exited.emit()
	button.release_focus()
	await wait_seconds(0.2)
	assert_eq(button.self_modulate, Color.WHITE)
	assert_eq(button.get_global_rect(), bounds)
	assert_signal_not_emitted(button, "pressed")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)

func test_panel_fades_in_but_close_returns_pause_focus_and_input_immediately() -> void:
	var origin: Button = (game.get_node("UILayer/HUD") as Hud).settings_button
	origin.grab_focus()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	watch_signals(settings)
	settings.open(true)
	assert_true(get_tree().paused)
	assert_true(settings.panel.visible)
	assert_lt(settings.panel.modulate.a, 1.0)
	assert_same(get_viewport().gui_get_focus_owner(), settings.close_button)
	await wait_seconds(0.2)
	assert_eq(settings.panel.modulate, Color.WHITE)
	settings.close()
	assert_false(settings.panel.visible)
	assert_false(get_tree().paused)
	assert_same(get_viewport().gui_get_focus_owner(), origin)
	var shade: Control = settings.get_node_or_null("Backdrop") as Control
	assert_not_null(shade)
	if shade == null: return
	assert_eq(shade.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	await wait_seconds(0.2)
	assert_false(shade.visible)
	assert_signal_emit_count(settings, "view_changed", 2)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)

func test_reopen_low_effects_and_fast_do_not_accept_stale_close_callbacks() -> void:
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	for fast: bool in [false, true]:
		game.call("_set_fast", fast, false)
		for reduced: bool in [false, true]:
			game.call("_set_low_effects", reduced, false)
			settings.open(false)
			settings.close()
			settings.open(false)
			await wait_seconds(0.22)
			assert_true(settings.panel.visible)
			assert_true(get_tree().paused)
			assert_eq(settings.panel.modulate, Color.WHITE)
			settings.close()
			assert_false(get_tree().paused)
			await wait_seconds(0.2)
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)

func test_low_effects_snaps_an_inflight_open_and_retirement_cannot_change_pause() -> void:
	settings.open(true)
	game.call("_set_low_effects", true, false)
	assert_eq(settings.panel.modulate, Color.WHITE)
	settings.close()
	var temporary: PlaybackSettings = SETTINGS.instantiate() as PlaybackSettings
	add_child_autofree(temporary)
	temporary.open(false)
	temporary.close()
	temporary.queue_free()
	get_tree().paused = true
	await wait_seconds(0.25)
	assert_true(get_tree().paused)
	get_tree().paused = false

func test_native_keyboard_activation_dispatches_once_and_keeps_focus() -> void:
	var button: FeedbackButton = preload("res://ui/feedback_button/feedback_button.tscn").instantiate() as FeedbackButton
	button.position = Vector2(100, 100)
	button.size = Vector2(120, 40)
	add_child_autofree(button)
	button.grab_focus()
	watch_signals(button)
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key)
	await wait_process_frames(2)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	get_viewport().push_input(key)
	await wait_process_frames(2)
	assert_signal_emit_count(button, "pressed", 1)
	assert_true(button.has_focus())
	button.disabled = true
	key.pressed = true
	get_viewport().push_input(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	get_viewport().push_input(key)
	await wait_process_frames(2)
	assert_signal_emit_count(button, "pressed", 1)

func test_feedback_is_local_and_hiding_cancels_a_held_tint() -> void:
	var scene: PackedScene = preload("res://ui/feedback_button/feedback_button.tscn")
	var first: FeedbackButton = scene.instantiate() as FeedbackButton
	var second: FeedbackButton = scene.instantiate() as FeedbackButton
	first.position = Vector2(100, 100)
	second.position = Vector2(300, 100)
	add_child_autofree(first)
	add_child_autofree(second)
	first.button_down.emit()
	await wait_seconds(0.2)
	assert_lt(first.self_modulate.r, 1.0)
	assert_eq(second.self_modulate, Color.WHITE)
	assert_eq(FeedbackButton.MOTION.pressed_tint, Color(0.90, 0.90, 0.90, 1.0))
	first.hide()
	assert_eq(first.self_modulate, Color.WHITE)
	first.show()
	await wait_seconds(0.2)
	assert_eq(first.self_modulate, Color.WHITE)
