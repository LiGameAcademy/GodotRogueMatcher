extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var board: Board = $Board
@onready var hud: Hud = $UILayer/HUD
@onready var feedback: GameFeedback = $GameFeedback
@onready var release_menu: ReleaseMenu = $MenuLayer/ReleaseMenu
@export var show_start_menu: bool = not OS.is_debug_build()
@export var persist_preferences: bool = true
var preferences: PlayerPreferences = PlayerPreferences.new()
@export var record_runs: bool = true
@export var collect_telemetry: bool = true
var board_rules: BoardRules
@export var enable_debug_fixtures: bool = true
var _fast_playback: bool = false
var _has_played: bool = false
var _menu_previous_pause: bool = false
var _menu_owns_pause: bool = false

func _ready() -> void:
	world_environment.environment = world_environment.environment.duplicate() as Environment
	if persist_preferences: preferences.load_values(CoreSystem.config_manager)
	GameManager.game_overed.connect(_on_game_over)
	GameManager.score_changed.connect(hud.show_score)
	GameManager.piece_count_changed.connect(hud.show_occupancy)
	GameManager.turn_started.connect(_on_turn_started)
	board.initialized.connect(_refresh_hud)
	board.initialized.connect(_update_board_layout)
	hud.board_area_changed.connect(_update_board_layout)
	board.presentation_updated.connect(_refresh_hud)
	board.director.busy_changed.connect(_on_playback_busy)
	board.score_presenter = _wait_for_score
	hud.fast_requested.connect(_set_fast)
	hud.pause_requested.connect(_toggle_pause)
	hud.help_requested.connect(_show_menu)
	release_menu.play_requested.connect(_play_from_menu)
	release_menu.tutorial_completed.connect(_tutorial_completed)
	get_window().focus_exited.connect(_pause_on_focus_loss)
	hud.skip_requested.connect(_request_skip)
	hud.low_effects_requested.connect(_set_low_effects)
	hud.volume_requested.connect(_preview_volume)
	hud.volume_committed.connect(_set_volume)
	board.feedback_requested.connect(feedback.play)
	board.director.playback_failed.connect(func(_reason: String) -> void: feedback.cancel())
	board.run_reset.connect(feedback.cancel)
	board.selection_changed.connect(_on_selection_feedback)
	board.selection_changed.connect(hud.show_selection)
	board.operation_feedback.connect(hud.show_status)
	_set_fast(preferences.fast, false)
	_set_low_effects(preferences.low_effects, false)
	_set_volume(preferences.volume, false)
	if collect_telemetry: board.telemetry_factory = TelemetryFactory.new()
	board_rules = BoardRules.new(BoardState.new(board.cols, board.rows), MatchSystem.MIN_MATCH_COUNT)
	await board.start_game(board_rules, record_runs)
	if show_start_menu: _show_menu()
	else: _has_played = true

func _exit_tree() -> void:
	if _menu_owns_pause: get_tree().paused = _menu_previous_pause

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var playback_key: InputEventKey = event as InputEventKey
		if playback_key.pressed and not playback_key.echo and playback_key.physical_keycode == KEY_F8:
			_set_fast(not _fast_playback)
	if OS.is_debug_build() and enable_debug_fixtures and event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F6:
			board.load_explosion_demo()
		elif key.pressed and not key.echo and key.physical_keycode == KEY_F7:
			board.open_skill_demo()

func _on_game_over() -> void:
	board.can_selected = false
	var active_run: RunController = board.run
	if not await board.finish_presentation() or board.run != active_run: return
	_refresh_hud()
	hud.show_status("棋盘已满 · 本局结束")
	feedback.play(&"finish")
	var popup: Control = await UIManager.open_popup("popup_game_over", {"score": GameManager.score, "summary": HudDetails.summary(active_run.state)})
	if is_instance_valid(popup):
		popup.retry_requested.connect(_on_retry_requested)
		popup.menu_requested.connect(_end_to_menu)

func _show_menu() -> void:
	if release_menu.visible or is_instance_valid(UIManager.current_popup): return
	_menu_previous_pause = get_tree().paused
	_menu_owns_pause = true
	get_tree().paused = true
	release_menu.open(_has_played, preferences.tutorial_seen, preferences.low_effects, GameManager.is_game_over)

func _play_from_menu(new_run: bool) -> void:
	get_tree().paused = false if new_run else _menu_previous_pause
	_menu_owns_pause = false
	_has_played = true
	hud.pause_button.text = "继续 / ESC" if get_tree().paused else "暂停 / ESC"
	if new_run: await _on_retry_requested()

func _pause_on_focus_loss() -> void:
	if _has_played and not get_tree().paused and not release_menu.visible:
		_toggle_pause()

func _tutorial_completed() -> void:
	preferences.tutorial_seen = true
	_save_preferences()

func _end_to_menu() -> void:
	UIManager.close_popup()
	_show_menu()

func _on_retry_requested() -> void:
	feedback.cancel()
	UIManager.close_popup()
	board_rules = BoardRules.new(BoardState.new(board.cols, board.rows), MatchSystem.MIN_MATCH_COUNT)
	await board.retry_game(board_rules)

func _set_fast(fast: bool, save: bool = true) -> void:
	_fast_playback = fast
	board.set_playback_fast(fast)
	hud.set_fast(fast)
	preferences.fast = fast
	if save: _save_preferences()

func _set_low_effects(enabled: bool, save: bool = true) -> void:
	preferences.low_effects = enabled
	board.view.set_low_effects(enabled)
	world_environment.environment.glow_enabled = not enabled
	hud.set_low_effects(enabled)
	if save: _save_preferences()

func _set_volume(volume: float, save: bool = true) -> void:
	preferences.volume = clampf(volume, 0.0, 1.0)
	feedback.set_volume(preferences.volume)
	hud.set_volume(preferences.volume)
	if save: _save_preferences()

func _save_preferences() -> void:
	if persist_preferences and not preferences.save_values(CoreSystem.config_manager):
		hud.show_status("设置保存失败，本次仍可使用")

func _preview_volume(volume: float) -> void:
	_set_volume(volume, false)

func _on_selection_feedback(piece: PieceState, _has_fuse: bool) -> void:
	if piece != null: feedback.play(&"select")

func _refresh_hud() -> void:
	hud.show_run(board.run)
	if board.run.state.pending_rewards > 0: hud.show_status("等待技能选择…")

func _on_turn_started(_turn: int) -> void:
	_refresh_hud()
	hud.show_status("请选择棋子与目标空格")

func _on_playback_busy(busy: bool) -> void:
	if busy: hud.show_status("正在结算与播放…")

func _wait_for_score() -> bool:
	hud.show_status("正在累计得分…")
	if board.director.skip_score_requested: hud.finish_score_now()
	return await hud.wait_for_score()

func _request_skip() -> void:
	if get_tree().paused or is_instance_valid(UIManager.current_popup): return
	var accepted: bool = board.director.request_skip()
	var score_skipped: bool = hud.finish_score_now()
	if accepted or score_skipped:
		feedback.cancel()
		hud.show_status("已请求略过可跳部分，必播动作仍需完成")

func _toggle_pause() -> void:
	if release_menu.visible: return
	if UIManager.current_popup is PopupSkillChoice:
		(UIManager.current_popup as PopupSkillChoice).toggle_selection_pause()
		return
	if is_instance_valid(UIManager.current_popup) or GameManager.is_game_over: return
	get_tree().paused = not get_tree().paused
	hud.pause_button.text = "继续 / ESC" if get_tree().paused else "暂停 / ESC"
	hud.show_status("已暂停" if get_tree().paused else ("请选择棋子与目标空格" if board.can_selected else "正在结算与播放…"))

func _update_board_layout() -> void:
	var bounds: Rect2 = board.view.transform * board.view.get_display_rect()
	if not bounds.has_area(): return
	var area: Rect2 = get_global_transform_with_canvas().affine_inverse() * hud.get_board_area()
	var factor: float = minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
	board.scale = Vector2.ONE * maxf(factor, 0.01)
	board.position = area.position + (area.size - bounds.size * factor) * 0.5 - bounds.position * factor
