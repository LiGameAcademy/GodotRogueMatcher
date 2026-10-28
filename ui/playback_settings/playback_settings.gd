class_name PlaybackSettings
extends CanvasLayer
## UI owns only its modal pause/focus; Game applies and persists player preferences.
signal view_changed(open: bool)
signal fast_requested(fast: bool)
signal low_effects_requested(enabled: bool)
signal volume_requested(volume: float)
signal volume_committed(volume: float)
signal skip_requested
signal menu_requested
signal board_signal_requested(enabled: bool)
signal background_motion_requested(enabled: bool)
signal theme_requested(theme_id: StringName)

const MOTION: UiMotionConfig = preload("res://ui/feedback_button/ui_motion_config.tres")

var _transition: Tween
var _transition_serial: int = 0
var _low_effects: bool = false
var _open: bool = false
var _previous_pause: bool = false
var _previous_focus: Control
var _volume_dragging: bool = false

@onready var panel: Control = $Panel
@onready var fast_button: CheckButton = %FastButton
@onready var low_effects_button: CheckButton = %LowEffectsButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var skip_button: FeedbackButton = %SkipButton
@onready var close_button: FeedbackButton = %Close
@onready var menu_button: FeedbackButton = %Menu
@onready var signal_button: CheckButton = %SignalButton
@onready var background_button: CheckButton = %BackgroundButton
@onready var theme_choice: OptionButton = %ThemeChoice
@onready var _backdrop: ColorRect = $Backdrop

func _ready() -> void:
	signal_button.toggled.connect(board_signal_requested.emit)
	background_button.toggled.connect(background_motion_requested.emit)
	close_button.pressed.connect(close)
	fast_button.toggled.connect(fast_requested.emit)
	low_effects_button.toggled.connect(low_effects_requested.emit)
	skip_button.pressed.connect(_skip)
	menu_button.pressed.connect(func() -> void:
		close()
		menu_requested.emit())
	volume_slider.value_changed.connect(_volume_changed)
	volume_slider.drag_started.connect(func() -> void: _volume_dragging = true)
	volume_slider.drag_ended.connect(_volume_drag_ended)
	theme_choice.item_selected.connect(func(index: int) -> void: theme_requested.emit(GameThemes.ALL[index].theme_id))
	_refresh_theme_labels()

func _exit_tree() -> void:
	_cancel_transition()
	if _open: get_tree().paused = _previous_pause

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		set_volume(volume_slider.value)
		_refresh_theme_labels()

func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey: return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_ESCAPE, KEY_F1: close()
			KEY_F8: fast_button.button_pressed = not fast_button.button_pressed
			KEY_F9:
				if not skip_button.disabled: _skip()
	if key.physical_keycode in [KEY_ESCAPE, KEY_F1, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]:
		get_viewport().set_input_as_handled()

func set_theme_id(theme_id: StringName) -> void:
	for index: int in range(GameThemes.ALL.size()):
		if GameThemes.ALL[index].theme_id == theme_id: theme_choice.select(index)

## Opens immediately, acquiring pause and focus before the visual transition.
func open(can_skip: bool, can_open_menu: bool = true) -> void:
	if _open: return
	_previous_pause = get_tree().paused
	_previous_focus = get_viewport().gui_get_focus_owner()
	_open = true
	skip_button.disabled = not can_skip
	menu_button.disabled = not can_open_menu
	get_tree().paused = true
	_cancel_transition()
	panel.modulate.a = 1.0 if _low_effects else 0.0
	if not _backdrop.visible: _backdrop.modulate.a = 0.0
	_backdrop.show()
	panel.show()
	if _low_effects:
		_backdrop.modulate.a = 1.0
	else:
		_transition = create_tween().set_parallel()
		_transition.tween_property(panel, "modulate:a", 1.0, MOTION.panel_duration)
		_transition.tween_property(_backdrop, "modulate:a", 1.0, MOTION.panel_duration)
	close_button.grab_focus()
	view_changed.emit(true)

## Releases modal input, pause and focus immediately; only the shade may linger.
func close() -> void:
	if not _open: return
	if _volume_dragging: volume_committed.emit(volume_slider.value)
	_volume_dragging = false
	_open = false
	_cancel_transition()
	panel.hide()
	panel.modulate = Color.WHITE
	if _low_effects:
		_backdrop.hide()
	else:
		var serial: int = _transition_serial
		_transition = create_tween()
		_transition.tween_property(_backdrop, "modulate:a", 0.0, MOTION.dismiss_duration)
		_transition.tween_callback(_finish_dismiss.bind(serial))
	get_tree().paused = _previous_pause
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree(): _previous_focus.grab_focus()
	view_changed.emit(false)

func set_fast(fast: bool) -> void:
	fast_button.set_pressed_no_signal(fast)

func set_board_signal(enabled: bool) -> void:
	signal_button.set_pressed_no_signal(enabled)

func set_background_motion(enabled: bool) -> void:
	background_button.set_pressed_no_signal(enabled)

## Cancels in-flight transitions and applies the same preference to child buttons.
func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	low_effects_button.set_pressed_no_signal(enabled)
	for button: FeedbackButton in [close_button, menu_button, skip_button]:
		button.set_low_effects(enabled)
	_cancel_transition()
	panel.modulate = Color.WHITE
	_backdrop.visible = _open
	_backdrop.modulate = Color.WHITE

func set_volume(volume: float) -> void:
	volume_slider.set_value_no_signal(volume)
	volume_slider.tooltip_text = tr("音量 %d%%（0 为静音）") % roundi(volume * 100.0)

func _refresh_theme_labels() -> void:
	var selected: int = maxi(0, theme_choice.selected)
	theme_choice.clear()
	for preset: GameTheme in GameThemes.ALL: theme_choice.add_item(tr(preset.title))
	theme_choice.select(selected)

func _skip() -> void:
	if skip_button.disabled: return
	close()
	skip_requested.emit()

func _volume_changed(volume: float) -> void:
	volume_requested.emit(volume)
	if not _volume_dragging: volume_committed.emit(volume)

func _volume_drag_ended(changed: bool) -> void:
	var commit: bool = changed and _volume_dragging
	_volume_dragging = false
	if commit: volume_committed.emit(volume_slider.value)

func _cancel_transition() -> void:
	_transition_serial += 1
	if _transition != null:
		_transition.kill()
		_transition = null

func _finish_dismiss(serial: int) -> void:
	if serial == _transition_serial and not _open: _backdrop.hide()
