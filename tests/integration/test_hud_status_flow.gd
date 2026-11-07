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
	board.can_selected = false
	game.call("_on_playback_busy", true)
	assert_eq(hud.status_label.text, "Resolving action…")
	game.call("_on_turn_started", 1)
	assert_eq(hud.status_label.text, "Resolving action…")
	board.can_selected = true
	assert_eq(hud.status_label.text, "Select a piece and an empty cell")
	board.operation_feedback.emit("hud.status.queued_target_invalid")
	assert_eq(hud.status_label.text, "Queued target is no longer valid. Choose again.")
	assert_eq(frozen, RunSnapshot.digest(RunSnapshot.capture(board.run)))

func test_input_notice_waits_for_permission_and_preserves_a_specific_status() -> void:
	board.input_permission = func(_active: RunController) -> bool: return false
	board.can_selected = false
	hud.show_status(&"hud.status.resolving")
	watch_signals(board)
	await board.resume_run(board.run)
	assert_false(board.can_selected)
	assert_signal_not_emitted(board, "input_ready")
	assert_ne(hud.status_label.text, "Select a piece and an empty cell")
	hud.show_status(&"hud.status.checkpoint_failed")
	board.input_permission = Callable()
	board.can_selected = true
	assert_signal_emit_count(board, "input_ready", 1)
	assert_eq(hud.status_label.text, "Could not save or restore your run. Please retry.")

func test_empty_manual_sweep_reports_acceptance_without_a_reject_or_score() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 128)
	var source: Vector2i = Vector2i.ZERO
	run.abilities.add_line_piece(LineClearState.AXIS_ROW, source, 0)
	run.state.rules.place_piece(Vector2i(8, 8), 1)
	run.start_turn()
	board._activate_run(run, false)
	board.view.rebuild(run.state.rules.state.get_snapshot())
	board.refresh_ability_markers()
	board.can_selected = true
	var cues: Array[StringName] = []
	board.feedback_requested.connect(func(cue: StringName) -> void: cues.append(cue))
	var notice_refills: Array[int] = []
	board.operation_feedback.connect(func(id: String) -> void:
		if id == "hud.status.activation_empty":
			notice_refills.append(run.state.spawn_history.size()))
	board._on_coordinate_pressed(source)
	assert_string_contains(hud.selection_label.text, "Row Sweeper")
	await board._on_piece_activated(source)
	assert_has(cues, &"reject")
	assert_eq(run.state.action_id, 0)
	run.state.line_clear.upgrades[&"line_manual_clear"] = 1
	cues.clear()
	await board._on_piece_activated(source)
	assert_has(cues, &"sweep")
	assert_does_not_have(cues, &"reject")
	assert_eq(run.state.action_id, 1)
	assert_eq(run.state.ledger.total, 0)
	assert_eq(run.state.spawn_history.size(), 3)
	assert_eq(notice_refills, [0])
	assert_eq(hud.selection_label.text, "Activated. No targets hit.")
	assert_eq(hud.breakdown_label.get_parsed_text(), "No score yet")
	hud.show_status(&"hud.status.checkpoint_saved")
	TranslationServer.set_locale("zh_CN")
	assert_eq(hud.selection_label.text, "已发动但未命中")
	board._on_coordinate_pressed(Vector2i(8, 8))
	assert_ne(hud.selection_label.text, "已发动但未命中")

func test_zero_events_preserve_the_latest_scoring_action_and_ledger() -> void:
	var ledger: ScoreLedger = ScoreLedger.new()
	ledger.commit(5, 1.0, 0, &"match", 1)
	ledger.commit(0, 1.0, 0, &"explosion", 1)
	ledger.commit(0, 1.0, 0, &"line_clear", 2)
	var details: String = HudDetails.score_details(ledger.get_entries())
	assert_string_contains(details, "+50")
	assert_false(details.contains("+0"))
	assert_eq(ledger.total, 50)
	assert_eq(ledger.get_entries().size(), 3)

func test_restored_score_without_scoring_details_keeps_the_hud_compact() -> void:
	var ledger: ScoreLedger = board.run.state.ledger
	assert_true(ledger.restore_checkpoint(100, 5))
	ledger.commit(0, 1.0, 0, &"line_clear", 1)
	hud.bind_checkpoint(board.run)
	assert_eq(hud.displayed_score, 100)
	assert_eq(hud.breakdown_label.custom_minimum_size.y, 32.0)
	assert_false(hud.score_label.tooltip_text.contains("+0"))
	var incomplete: String = tr("实际构成：行动 %d + 选卡 %d + 其他 %d = %d") % [0, 0, 0, 100]
	assert_false(hud.score_label.tooltip_text.contains(incomplete))

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
