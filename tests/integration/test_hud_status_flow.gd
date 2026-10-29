extends GutTest

## Exercises real HUD producers and language refresh without changing rule state.
const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var hud: Hud
var previous_locale: String
var previous_preference: String

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	previous_locale = TranslationServer.get_locale()
	previous_preference = CoreSystem.localization_manager.get_preferred_locale()
	TranslationServer.set_locale("en_US")
	get_tree().paused = false
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	await wait_process_frames(2)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	CoreSystem.localization_manager.set_preferred_locale(previous_preference)
	TranslationServer.set_locale(previous_locale)

func test_initial_english_and_all_statuses_refresh_text_and_tooltip() -> void:
	assert_eq(hud.status_label.text, "Select a piece and an empty cell")
	var frozen: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	for suffix: StringName in HudStatusMessages.IDS:
		var id: StringName = StringName("hud.status." + String(suffix))
		var parameters: Dictionary = {}
		if suffix == &"spawn_progress": parameters = {"current": 1, "total": 3}
		if suffix == &"capture_refill_used": parameters = {"count": 1}
		hud.show_status(id, parameters)
		var english: String = hud.status_label.text
		TranslationServer.set_locale("zh_CN")
		assert_ne(hud.status_label.text, english, id)
		assert_eq(hud.status_label.text, hud.status_label.tooltip_text, id)
		TranslationServer.set_locale("en_US")
		assert_eq(hud.status_label.text, english, id)
		assert_eq(hud.status_label.text, hud.status_label.tooltip_text, id)
	assert_eq(frozen, RunSnapshot.digest(RunSnapshot.capture(board.run)))
	assert_false(get_tree().paused)

func test_parameter_snapshot_and_updates_survive_switch_without_rule_mutation() -> void:
	var parameters: Dictionary = {"current": 1, "total": 3}
	hud.show_status(&"hud.status.spawn_progress", parameters)
	parameters.current = 2
	TranslationServer.set_locale("zh_CN")
	assert_eq(hud.status_label.text, "正在补棋：1/3")
	hud.show_status(&"hud.status.spawn_progress", parameters)
	TranslationServer.set_locale("en_US")
	assert_eq(hud.status_label.text, "Spawning pieces: 2/3")
	assert_eq(hud.status_label.tooltip_text, hud.status_label.text)

func test_real_pause_busy_score_and_buffer_feedback_routes() -> void:
	var frozen: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	game.call("_toggle_pause")
	assert_true(get_tree().paused)
	assert_eq(hud.status_label.text, "Paused")
	TranslationServer.set_locale("zh_CN")
	assert_true(get_tree().paused)
	assert_eq(hud.status_label.text, "已暂停")
	TranslationServer.set_locale("en_US")
	game.call("_toggle_pause")
	game.call("_on_playback_busy", true)
	assert_eq(hud.status_label.text, "Resolving action…")
	game.call("_on_turn_started", 1)
	assert_eq(hud.status_label.text, "Select a piece and an empty cell")
	board.operation_feedback.emit("hud.status.queued_target_invalid")
	assert_eq(hud.status_label.text, "Queued target is no longer valid. Choose again.")
	assert_eq(frozen, RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_terminal_message_retranslates_instead_of_caching_translated_text() -> void:
	board.run.state.is_game_over = true
	board.run.state.end_reason = &"board_full"
	await game.call("_on_game_over")
	assert_eq(hud.status_label.text, "Board full. Run over!")
	TranslationServer.set_locale("zh_CN")
	assert_eq(hud.status_label.text, "棋盘已满，本局结束")
	var frozen: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	TranslationServer.set_locale("en_US")
	assert_eq(hud.status_label.text, "Board full. Run over!")
	assert_eq(hud.status_label.text, hud.status_label.tooltip_text)
	assert_eq(frozen, RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_language_service_refresh_preserves_current_message_during_reward_wait() -> void:
	assert_eq(CoreSystem.localization_manager.set_preferred_locale("en_US"), OK)
	board.run.state.pending_rewards = 1
	hud.show_status(&"hud.status.spawn_progress", {"current": 1, "total": 3})
	var frozen: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_eq(CoreSystem.localization_manager.set_preferred_locale("zh_CN"), OK)
	assert_eq(hud.status_label.text, "正在补棋：1/3", "locale refresh must retain the current ID and parameters")
	assert_eq(CoreSystem.localization_manager.set_preferred_locale("en_US"), OK)
	assert_eq(hud.status_label.text, "Spawning pieces: 1/3")
	assert_eq(frozen, RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_internal_reason_never_becomes_player_text() -> void:
	var frozen: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	var flow: GameRewardFlow = game.get("_reward_flow") as GameRewardFlow
	flow.error_reported.emit("reward_presentation_failed")
	assert_eq(hud.status_label.text, "Status message unavailable")
	TranslationServer.set_locale("zh_CN")
	assert_eq(hud.status_label.text, "状态提示暂不可用")
	assert_eq(hud.status_label.text, hud.status_label.tooltip_text)
	assert_eq(frozen, RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_status_accepts_tooltip_hover_without_covering_board_or_pause_button() -> void:
	assert_eq(hud.status_label.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_false(hud.status_label.get_global_rect().intersects(hud.board_area.get_global_rect()))
	assert_false(hud.status_label.get_global_rect().intersects(hud.pause_button.get_global_rect()))
	assert_false(hud.status_label.tooltip_text.is_empty())
