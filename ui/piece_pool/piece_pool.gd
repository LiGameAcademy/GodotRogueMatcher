class_name PiecePool
extends Control

signal pool_view_changed(open: bool)

@onready var button: Button = $Button
@onready var panel: PanelContainer = $Panel
@onready var details: Label = $Panel/Content/Details
@onready var hide_timer: Timer = $HideTimer
var _description: String = ""
var _pinned: bool = false

func _ready() -> void:
	button.pressed.connect(_toggle_pin)
	button.mouse_entered.connect(open)
	button.mouse_exited.connect(_schedule_hide)
	panel.mouse_entered.connect(hide_timer.stop)
	panel.mouse_exited.connect(_schedule_hide)
	hide_timer.timeout.connect(_hide_hover)
	($Panel/Content/Close as Button).pressed.connect(close)
	set_process(false)
	update_minimum_size()

func _get_minimum_size() -> Vector2:
	return $Button.get_combined_minimum_size() if is_node_ready() else Vector2(76, 38)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): update_minimum_size()

func _process(_delta: float) -> void:
	_place_panel()

func _input(event: InputEvent) -> void:
	if not panel.visible: return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
	elif _pinned and event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not panel.get_global_rect().has_point(click.position) and not button.get_global_rect().has_point(click.position):
			close()
			get_viewport().set_input_as_handled()

func show_state(state: RunState) -> void:
	_description = SpawnPoolText.describe(state)
	details.text = _description

func open() -> void:
	if _description.is_empty(): return
	hide_timer.stop()
	if panel.visible: return
	panel.show()
	set_process(true)
	_place_panel()
	pool_view_changed.emit(true)

func close() -> void:
	hide_timer.stop()
	_pinned = false
	set_process(false)
	if not panel.visible: return
	panel.hide()
	pool_view_changed.emit(false)

func _toggle_pin() -> void:
	if _pinned: close()
	else:
		open()
		_pinned = true

func _schedule_hide() -> void:
	if not _pinned: hide_timer.start()

func _hide_hover() -> void:
	if _pinned or button.get_global_rect().has_point(get_global_mouse_position()) or panel.get_global_rect().has_point(get_global_mouse_position()): return
	close()

func _place_panel() -> void:
	var viewport_rect: Rect2 = get_viewport_rect().grow(-12.0)
	var origin: Vector2 = button.get_global_rect().position + Vector2(0, button.size.y + 6)
	origin.x = clampf(origin.x, viewport_rect.position.x, maxf(viewport_rect.position.x, viewport_rect.end.x - panel.size.x))
	origin.y = clampf(origin.y, viewport_rect.position.y, maxf(viewport_rect.position.y, viewport_rect.end.y - panel.size.y))
	panel.global_position = origin
