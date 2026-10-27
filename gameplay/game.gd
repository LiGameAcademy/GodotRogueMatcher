extends Node2D

## Coordinates scene children, preferences, reward UI and presentation for one game.
## Rules remain in Board/RunController; this scene owns UI pause and restart policy.

## Requests restart from an explicit host instead of replacing its scene.
signal restart_requested

const GAME_OVER_POPUP: Script = preload("res://ui/popup_game_over.gd")

## Delegates restart to the host; all other exports configure scene startup.
@export var use_external_restart: bool = false
@export var collection_context: String = "unknown"
@export var intercept_window_close: bool = false
@export var show_start_menu: bool = not OS.is_debug_build()
@export var persist_preferences: bool = true
@export var record_runs: bool = true
@export var collect_telemetry: bool = true
@export var enable_debug_fixtures: bool = true

## Host-visible preference and fixture state; writes must precede startup or use UI actions.
var preferences: PlayerPreferences = PlayerPreferences.new()
var board_rules: BoardRules
var game_theme: GameTheme
var _reward_flow: GameRewardFlow = GameRewardFlow.new()

var _settings_previous_location: String = ""
var _pool_previous_location: String = ""
var _restart_reason: String = "restart"
var _fast_playback: bool = false
var _has_played: bool = false
var _menu_previous_pause: bool = false
var _menu_owns_pause: bool = false

@onready var _background: GameBackground = $GameBackground
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _board: Board = $Board
@onready var _hud: Hud = $UILayer/HUD
@onready var _feedback: GameFeedback = $GameFeedback
## Kept public for existing host-scene menu integration.
@onready var release_menu: ReleaseMenu = $MenuLayer/ReleaseMenu
@onready var _collection: RunCollection = $RunCollection
@onready var _card_transfer: CardTransfer = $CardTransfer
@onready var _skill_pool: SkillPool = $SkillPool
@onready var _settings: PlaybackSettings = $PlaybackSettings

func _ready() -> void:
	_world_environment.environment = _world_environment.environment.duplicate() as Environment
	if persist_preferences: preferences.load_values(CoreSystem.config_manager)
	_connect_run_signals()
	_connect_menu_signals()
	_connect_settings_signals()
	_set_background_motion(preferences.background_motion, false)
	_set_board_signal(preferences.board_signal, false)
	_set_fast(preferences.fast, false)
	_set_low_effects(preferences.low_effects, false)
	_set_volume(preferences.volume, false)
	# Apply the saved skin before start_game yields for initial spawn presentation.
	_set_theme(preferences.theme_id, false)
	if collect_telemetry and not OS.has_feature("web"):
		_collection.configure(collection_context)
		_board.telemetry_factory = _collection.factory
	_connect_collection_controls(release_menu.collection_controls)
	if intercept_window_close: get_tree().auto_accept_quit = false
	board_rules = BoardRules.new(BoardState.new(_board.cols, _board.rows), MatchSystem.MIN_MATCH_COUNT)
	await _board.start_game(board_rules, record_runs)
	if show_start_menu: _show_menu()
	else:
		_has_played = true
		if _board.observation.telemetry != null: _board.observation.telemetry.play_started()

func _exit_tree() -> void:
	_reward_flow.cancel()
	if _menu_owns_pause: get_tree().paused = _menu_previous_pause
	if intercept_window_close: get_tree().auto_accept_quit = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and intercept_window_close: _quit("window_close_requested")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var playback_key: InputEventKey = event as InputEventKey
		if playback_key.pressed and not playback_key.echo and playback_key.physical_keycode == KEY_F8:
			_set_fast(not _fast_playback)
	if OS.is_debug_build() and enable_debug_fixtures and event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F6:
			_board.load_explosion_demo()
		elif key.pressed and not key.echo and key.physical_keycode == KEY_F10:
			if await _board.load_explosion_demo("fixture_dye"):
				_hud.show_status("染色试玩：将第5列第7行红棋移到第5列第5行")
		elif key.pressed and not key.echo and key.physical_keycode == KEY_F11:
			if key.alt_pressed:
				if await _board.load_explosion_demo("fixture_manual_limit"):
					_hud.show_status("限次试玩：依次双击四枚扫线手；前三次生效，第四次保留")
				return
			var wide: bool = key.shift_pressed
			var cross: bool = key.ctrl_pressed
			if wide and cross:
				if await _board.load_explosion_demo("fixture_line_score"):
					_hud.show_status("得分试玩：双击扫线手；清2枚，基础14分+额外4分")
				return
			var mode: String = "fixture_line_cross" if cross else ("fixture_line_span" if wide else "fixture_line")
			if await _board.load_explosion_demo(mode):
				_hud.show_status("十字连携试玩：双击左侧行扫手，观察行→列→爆破手" if cross else ("跨度试玩：双击扫线手，清连续3行或3列；边缘截断" if wide else "扫线试玩：双击行或列清除手；每条线清2枚，得14基础分"))
		elif key.pressed and not key.echo and key.physical_keycode == KEY_F7:
			_board.open_skill_demo()
		elif key.pressed and not key.echo and key.physical_keycode == KEY_F12:
			if await _board.load_explosion_demo("fixture_transform"):
				_hud.show_status("转化试玩：三选一将普通棋改装，保留原色与位置；已有引信和爆破手不受影响")
				var active_run: RunController = _board.run
				_board.can_selected = false
				await BoardRunFlow.continue_run(_board, active_run)
				if _board.run == active_run: _board.can_selected = not active_run.state.is_game_over and active_run.state.rule_error.is_empty()

## Resumes an explicitly requested reward choice; closing its popup does not reopen it.
func request_rewards() -> void:
	var active: RunController = _board.run
	if active.state.pending_rewards <= 0 or active.state.is_game_over or not active.state.rule_error.is_empty(): return
	_board.can_selected = false
	var step: RunStepResult = active.advance()
	if step.kind == &"offer": _reward_flow.present(_board, active, step.offer, true)

func _connect_run_signals() -> void:
	GameManager.game_overed.connect(_on_game_over)
	GameManager.score_changed.connect(_hud.show_score)
	GameManager.piece_count_changed.connect(_hud.show_occupancy)
	GameManager.turn_started.connect(_on_turn_started)
	_board.initialized.connect(_refresh_hud)
	_board.initialized.connect(func() -> void: _collection.bind(_board.run))
	_board.initialized.connect(_update_board_layout)
	_hud.board_area_changed.connect(_update_board_layout)
	_board.presentation_updated.connect(_refresh_hud)
	_board.director.busy_changed.connect(_on_playback_busy)
	_board.score_presenter = _wait_for_score
	_board.reward_requested.connect(_on_reward_requested)
	_board.run_reset.connect(_reward_flow.cancel)
	_board.run_reset.connect(_background.reset_visual)
	_board.run_reset.connect(_feedback.cancel)
	_board.run_reset.connect(_hud.reset_score_effects)
	_board.run_reset.connect(_card_transfer.cancel)
	_reward_flow.resume_available.connect(_hud.set_reward_waiting)
	_reward_flow.selection_committed.connect(_on_reward_committed)
	_reward_flow.error_reported.connect(_hud.show_status)
	_hud.reward_resume_requested.connect(request_rewards)
	_board.feedback_requested.connect(_feedback.play)
	_board.match_feedback_requested.connect(_feedback.play_match)
	_board.director.playback_failed.connect(func(_reason: String) -> void: _feedback.cancel())
	_board.view.score_floats.score_visualized.connect(_on_score_visualized)
	_board.goal_bonus_ready.connect(_on_goal_bonus_ready)
	_hud.piece_pool_visibility_changed.connect(_on_piece_pool_visibility_changed)
	_board.selection_changed.connect(_on_selection_feedback)
	_board.selection_changed.connect(_hud.show_selection)
	_board.operation_feedback.connect(_hud.show_status)
	_collection.status_changed.connect(_show_collection_status)

func _connect_menu_signals() -> void:
	_hud.pause_requested.connect(_toggle_pause)
	_hud.settings_requested.connect(_open_settings)
	_settings.menu_requested.connect(_show_menu)
	release_menu.settings_requested.connect(_open_settings)
	release_menu.skill_pool_requested.connect(_open_skill_pool)
	release_menu.mode_requested.connect(_select_mode)
	release_menu.play_requested.connect(_play_from_menu)
	release_menu.tutorial_completed.connect(_tutorial_completed)
	release_menu.language_requested.connect(_set_language)
	release_menu.set_language_preference(CoreSystem.localization_manager.get_preferred_locale())
	_skill_pool.view_changed.connect(_on_skill_pool_view_changed)
	UIManager.popup_opened.connect(_on_popup_opened)
	CoreSystem.localization_manager.locale_changed.connect(_on_locale_changed)
	get_window().focus_exited.connect(_pause_on_focus_loss)

func _connect_settings_signals() -> void:
	_settings.fast_requested.connect(_set_fast)
	_settings.view_changed.connect(_on_settings_view_changed)
	_hud.skip_requested.connect(_request_skip)
	_settings.skip_requested.connect(_request_skip)
	_settings.low_effects_requested.connect(_set_low_effects)
	_settings.volume_requested.connect(_preview_volume)
	_settings.volume_committed.connect(_set_volume)
	_settings.theme_requested.connect(_set_theme)
	_settings.background_motion_requested.connect(_set_background_motion)
	_settings.board_signal_requested.connect(_set_board_signal)

func _set_language(preference: String) -> void:
	var error: Error = CoreSystem.localization_manager.set_preferred_locale(preference, persist_preferences)
	if error != OK:
		push_warning("Language preference: " + error_string(error))
		release_menu.show_language_error()

func _show_menu() -> void:
	if release_menu.visible or is_instance_valid(UIManager.current_popup): return
	_hud.piece_pool.close()
	_menu_previous_pause = get_tree().paused
	_menu_owns_pause = true
	get_tree().paused = true
	release_menu.open(_has_played, preferences.tutorial_seen, preferences.low_effects, GameManager.is_game_over, _board.run.state.mode_id())
	_set_collection_location("help" if _has_played else "start_menu")
	_collection.flush()

func _play_from_menu(new_run: bool) -> void:
	get_tree().paused = false if new_run else _menu_previous_pause
	_menu_owns_pause = false
	_has_played = true
	_hud.show_pause_state(get_tree().paused)
	if new_run: await _on_retry_requested()
	else: _set_collection_location("")
	if _board.observation.telemetry != null: _board.observation.telemetry.play_started()

func _pause_on_focus_loss() -> void:
	if _has_played and not get_tree().paused and not release_menu.visible:
		_toggle_pause()

func _tutorial_completed() -> void:
	preferences.tutorial_seen = true
	_save_preferences()

func _end_to_menu() -> void:
	BoardRunFlow.finalize(_board.run, "result_to_menu")
	UIManager.close_popup()
	_show_menu()

func _continue_challenge() -> void:
	if not _board.run.can_continue_challenge(): return
	UIManager.close_popup()
	_set_collection_location("")
	var active: RunController = _board.run
	await _board.continue_challenge()
	if not is_instance_valid(_board) or _board.run != active: return
	_refresh_hud()

func _set_fast(fast: bool, save: bool = true) -> void:
	_fast_playback = fast
	_board.set_playback_fast(fast)
	_hud.set_fast(fast)
	_settings.set_fast(fast)
	preferences.fast = fast
	if save: _save_preferences()

func _set_low_effects(enabled: bool, save: bool = true) -> void:
	preferences.low_effects = enabled
	_background.set_low_effects(enabled)
	_board.view.set_low_effects(enabled)
	_world_environment.environment.glow_enabled = not enabled
	_hud.set_low_effects(enabled)
	_settings.set_low_effects(enabled)
	release_menu.set_low_effects(enabled)
	if enabled: _card_transfer.cancel()
	if is_instance_valid(UIManager.current_popup) and UIManager.current_popup is PopupSkillChoice:
		(UIManager.current_popup as PopupSkillChoice).set_low_effects(enabled)
	if save: _save_preferences()

func _set_board_signal(enabled: bool, save: bool = true) -> void:
	preferences.board_signal = enabled
	_board.view.set_signal_enabled(enabled)
	_settings.set_board_signal(enabled)
	if save: _save_preferences()

func _set_background_motion(enabled: bool, save: bool = true) -> void:
	preferences.background_motion = enabled
	_background.set_motion_enabled(enabled)
	_settings.set_background_motion(enabled)
	if save: _save_preferences()

func _set_volume(volume: float, save: bool = true) -> void:
	preferences.volume = clampf(volume, 0.0, 1.0)
	_feedback.set_volume(preferences.volume)
	_settings.set_volume(preferences.volume)
	if save: _save_preferences()

func _save_preferences() -> void:
	if persist_preferences and not preferences.save_values(CoreSystem.config_manager):
		_hud.show_status("设置保存失败，本次仍可使用")

func _preview_volume(volume: float) -> void:
	_set_volume(volume, false)

func _open_skill_pool() -> void:
	_feedback.play(&"confirm")
	_skill_pool.open(_board.run)

func _open_settings() -> void:
	if _settings.panel.visible or _skill_pool.panel.visible: return
	_feedback.play(&"confirm")
	_hud.piece_pool.close()
	_settings_previous_location = _collection.ui if _collection.ui in ["help", "start_menu", "result", "pause"] else ""
	_settings.open(not get_tree().paused and not is_instance_valid(UIManager.current_popup), not is_instance_valid(UIManager.current_popup))

func _set_theme(theme_id: StringName, save: bool = true) -> void:
	var preset: GameTheme = GameThemes.find(theme_id)
	if not preset.validation_error().is_empty():
		_hud.show_status("画面主题配置无效")
		return
	game_theme = preset
	preferences.theme_id = preset.theme_id
	_apply_game_theme()
	_settings.set_theme_id(preset.theme_id)
	if save: _save_preferences()

## Applies the selected read-only preset to scene-owned presentation children.
func _apply_game_theme() -> void:
	if game_theme == null: return
	_background.size = get_viewport_rect().size
	_background.apply_game_theme(game_theme)
	_hud.apply_game_theme(game_theme)
	_board.view.apply_game_theme(game_theme)
	GameThemeUi.apply(release_menu, game_theme)
	GameThemeUi.apply(_settings, game_theme)
	_skill_pool.apply_game_theme(game_theme)
	GameThemeUi.apply(_card_transfer, game_theme)
	if is_instance_valid(UIManager.current_popup): GameThemeUi.apply(UIManager.current_popup, game_theme)

func _refresh_hud() -> void:
	_hud.show_run(_board.run)
	if _board.run.state.pending_rewards > 0: _hud.show_status("等待技能选择…")

## Waits for HUD presentation only; committed score is never calculated here.
func _wait_for_score() -> bool:
	_hud.show_status("正在累计得分…")
	if _board.director.skip_score_requested: _hud.finish_score_now()
	return await _hud.wait_for_score()

func _request_skip() -> void:
	if get_tree().paused or is_instance_valid(UIManager.current_popup): return
	var accepted: bool = _board.director.request_skip()
	var score_skipped: bool = _hud.finish_score_now()
	if accepted or score_skipped:
		_feedback.cancel()
		_hud.show_status("已请求略过可跳部分，必播动作仍需完成")

func _toggle_pause() -> void:
	_feedback.play(&"confirm")
	if release_menu.visible: return
	if is_instance_valid(UIManager.current_popup) and UIManager.current_popup is PopupSkillChoice:
		(UIManager.current_popup as PopupSkillChoice).toggle_selection_pause()
		return
	if is_instance_valid(UIManager.current_popup) or GameManager.is_game_over: return
	get_tree().paused = not get_tree().paused
	_hud.show_pause_state(get_tree().paused)
	_hud.show_status("已暂停" if get_tree().paused else ("请选择棋子与目标空格" if _board.can_selected else "正在结算与播放…"))
	_collection.location("pause" if get_tree().paused else "board_input" if _board.can_selected else "presentation")

func _update_board_layout() -> void:
	# A Control under Node2D has no parent Control to stretch against.
	_background.size = get_viewport_rect().size
	var bounds: Rect2 = _board.view.transform * _board.view.get_display_rect()
	if not bounds.has_area(): return
	var area: Rect2 = get_global_transform_with_canvas().affine_inverse() * _hud.get_board_area()
	var factor: float = minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
	_board.scale = Vector2.ONE * maxf(factor, 0.01)
	_board.position = area.position + (area.size - bounds.size * factor) * 0.5 - bounds.position * factor

func _select_mode(mode_id: StringName) -> void:
	var mode: GameModeDefinition = GameModes.find(mode_id)
	if mode != null:
		if _board.run != null and _board.run.state.mode_id() != mode_id: _restart_reason = "mode_switch"
		_board.game_mode = mode

func _set_collection_location(location: String) -> void:
	_board.observation.ui_location(location)
	_collection.location(location if not location.is_empty() else "board_input" if _board.can_selected else "presentation")

func _connect_collection_controls(controls: CollectionControls) -> void:
	if controls == null: return
	controls.folder_requested.connect(_collection.open_directory)
	controls.export_requested.connect(_collection.export_files)
	controls.quit_requested.connect(_quit.bind("quit_button"))
	controls.show_status(_collection.save_status(), _collection.enabled, intercept_window_close)

func _show_collection_status(message: String) -> void:
	release_menu.collection_controls.show_status(message, _collection.enabled, intercept_window_close)
	if UIManager.current_popup is GAME_OVER_POPUP:
		(UIManager.current_popup as GAME_OVER_POPUP).collection_controls.show_status(message, _collection.enabled, intercept_window_close)

func _quit(reason: String) -> void:
	if not intercept_window_close: return
	_board.can_selected = false
	_board.cancel_buffered_input("window_close")
	_collection.close(reason)
	get_tree().quit()

func _on_locale_changed(_old: String, _new: String) -> void:
	if _board.run == null: return
	_refresh_hud()
	_board.view.refresh_piece_details(_board.run.state.rules.state.get_snapshot(), _board.run.state.explosion, _board.run.abilities.config, _board.run.state.line_clear, _board.run.state.manual_uses_used)
	_hud.show_pause_state(get_tree().paused)

func _on_game_over() -> void:
	_board.can_selected = false
	var active_run: RunController = _board.run
	if not await _board.finish_presentation() or _board.run != active_run: return
	_refresh_hud()
	_hud.show_status(StageText.end_title(active_run.state))
	if active_run.state.end_reason != &"challenge_completed": _feedback.play(&"finish")
	var popup: Control = await UIManager.open_popup("popup_game_over", {"score": GameManager.score, "summary": HudDetails.summary(active_run.state), "run_state": active_run.state, "can_continue": active_run.can_continue_challenge()})
	if is_instance_valid(popup):
		popup.retry_requested.connect(_on_retry_requested)
		popup.continue_requested.connect(_continue_challenge)
		popup.menu_requested.connect(_end_to_menu)
		if popup is GAME_OVER_POPUP: _connect_collection_controls((popup as GAME_OVER_POPUP).collection_controls)
	_set_collection_location("result")

func _on_retry_requested() -> void:
	if use_external_restart:
		restart_requested.emit()
		return
	_settings.close()
	_skill_pool.close()
	_collection.finish(_restart_reason)
	_restart_reason = "restart"
	_feedback.cancel()
	UIManager.close_popup()
	board_rules = BoardRules.new(BoardState.new(_board.cols, _board.rows), MatchSystem.MIN_MATCH_COUNT)
	await _board.retry_game(board_rules)
	_apply_game_theme()
	_set_collection_location("")
	if _board.observation.telemetry != null: _board.observation.telemetry.play_started()

func _on_selection_feedback(piece: PieceState, _has_fuse: bool) -> void:
	if piece != null: _feedback.play(&"select")

func _on_score_visualized(entry: ScoreEntry, origin: Vector2) -> void:
	_background.respond_to_score(entry.final_score)
	_hud.show_score_burst(entry, _board.view.score_floats.get_global_transform_with_canvas() * origin)

func _on_goal_bonus_ready(entry: ScoreEntry) -> void:
	_background.respond_to_score(entry.final_score)
	_hud.show_score_burst(entry, _hud.score_label.get_global_rect().get_center())

func _on_popup_opened(popup: Control) -> void:
	if game_theme != null: GameThemeUi.apply(popup, game_theme)
	if popup is PopupSkillChoice:
		(popup as PopupSkillChoice).settings_requested.connect(_open_settings)
		(popup as PopupSkillChoice).skill_pool_requested.connect(_open_skill_pool)
		(popup as PopupSkillChoice).card_acquired.connect(_on_skill_card_acquired)
		(popup as PopupSkillChoice).set_low_effects(preferences.low_effects)

func _on_reward_requested(active: RunController, offer: SkillOffer) -> void:
	_reward_flow.present(_board, active, offer)

func _on_reward_committed(active: RunController) -> void:
	_feedback.play(&"acquire")
	await _board.resume_run(active)
	if _board.run == active: _refresh_hud()

func _on_settings_view_changed(open: bool) -> void:
	_board.observation.paused(get_tree().paused and (open or not UIManager.current_popup is PopupSkillChoice))
	_set_collection_location("settings" if open else _settings_previous_location)
	_collection.flush()

func _on_skill_card_acquired(skill: SkillDefinition, target: SkillTarget, source: Rect2) -> void:
	var destination: Rect2 = _hud.build_list.get_global_rect() if skill.is_persistent or skill.refill_effect() != null else _hud.history_button.get_global_rect()
	_card_transfer.play(skill, target, source, destination, preferences.low_effects)

func _on_skill_pool_view_changed(open: bool) -> void:
	if open:
		_pool_previous_location = _collection.ui
		_set_collection_location("skill_pool")
	else:
		_set_collection_location(_pool_previous_location)

func _on_piece_pool_visibility_changed(open: bool) -> void:
	_set_collection_location("piece_pool" if open else "")

func _on_turn_started(_turn: int) -> void:
	_refresh_hud()
	_hud.show_status("请选择棋子与目标空格")

func _on_playback_busy(busy: bool) -> void:
	if busy: _hud.show_status("正在结算与播放…")
