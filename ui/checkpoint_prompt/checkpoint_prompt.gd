class_name CheckpointPrompt
extends CanvasLayer

## Presents save/load progress and explicit retry/leave/cancel choices; owns no run state.
signal action_requested(action: StringName)
var _message: StringName = &"checkpoint.working"
var _kind: StringName = &"busy"
@onready var _panel: Control = $Panel
@onready var _message_label: Label = %Message
@onready var primary: Button = %Primary
@onready var leave_old: Button = %LeaveOld
@onready var cancel_button: Button = %Cancel

func _ready() -> void:
	primary.pressed.connect(func() -> void: action_requested.emit(&"confirm" if _kind == &"confirm" else &"retry"))
	leave_old.pressed.connect(func() -> void: action_requested.emit(&"leave_old"))
	cancel_button.pressed.connect(func() -> void: action_requested.emit(&"cancel"))
	_panel.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): _refresh()

func _input(event: InputEvent) -> void:
	if is_node_ready() and _panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		action_requested.emit(&"cancel")
	elif is_node_ready() and _panel.visible and event is InputEventKey:
		if (event as InputEventKey).physical_keycode in [KEY_F1, KEY_F6, KEY_F7, KEY_F8, KEY_F10, KEY_F11, KEY_F12]:
			get_viewport().set_input_as_handled()

func open(message: StringName, kind: StringName = &"busy") -> void:
	_message = message
	_kind = kind
	_refresh()
	_panel.show()
	cancel_button.grab_focus()

func close() -> void:
	_panel.hide()

func is_open() -> bool:
	return _panel.visible

func _refresh() -> void:
	_message_label.text = tr(_message)
	primary.text = tr("checkpoint.confirm_new" if _kind == &"confirm" else "checkpoint.retry")
	leave_old.text = tr("checkpoint.leave_unverified_terminal" if _kind == &"terminal_failed" else "checkpoint.leave_old")
	cancel_button.text = tr("checkpoint.cancel")
	primary.visible = _kind in [&"confirm", &"save_failed", &"invalidate_failed", &"terminal_failed"]
	leave_old.visible = _kind in [&"save_failed", &"terminal_failed"]
