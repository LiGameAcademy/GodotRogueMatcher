class_name FeedbackButton
extends Button

## Adds tint feedback without moving hit bounds or dispatching button actions.
const MOTION: UiMotionConfig = preload("res://ui/feedback_button/ui_motion_config.tres")
var _rest_color: Color = Color.WHITE
var _held: bool = false
var _hovered: bool = false
var _was_disabled: bool = false
var _low_effects: bool = false
var _feedback_tween: Tween

func _ready() -> void:
	_rest_color = self_modulate
	_was_disabled = disabled
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_refresh_feedback)
	focus_exited.connect(_on_focus_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	visibility_changed.connect(_on_visibility_changed)

func _exit_tree() -> void:
	_cancel_feedback()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and is_node_ready() and _was_disabled != disabled:
		_was_disabled = disabled
		if disabled: _held = false
		_refresh_feedback()

## Snaps visual state when reduced effects are requested; actions stay native.
func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	_refresh_feedback()

func _cancel_feedback() -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
		_feedback_tween = null

func _refresh_feedback() -> void:
	if not is_node_ready(): return
	_cancel_feedback()
	var target: Color = _rest_color
	if is_visible_in_tree() and not disabled:
		if _held: target *= MOTION.pressed_tint
		elif _hovered or has_focus(): target *= MOTION.hover_tint
	if _low_effects or not is_visible_in_tree():
		self_modulate = target
		return
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(self, "self_modulate", target, MOTION.button_duration)

func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_feedback()

func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_feedback()

func _on_focus_exited() -> void:
	_held = false
	_refresh_feedback()

func _on_button_down() -> void:
	_held = not disabled
	_refresh_feedback()

func _on_button_up() -> void:
	_held = false
	_refresh_feedback()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_held = false
		_hovered = false
	_refresh_feedback()
