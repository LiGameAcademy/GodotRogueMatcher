class_name GoalProgress
extends HBoxContainer

signal animation_changed
signal value_changed(value: int)

const MOTE: PackedScene = preload("res://ui/goal_progress/score_mote.tscn")
@export var config: GoalProgressConfig = preload("res://ui/goal_progress/goal_progress_config.tres")
@onready var current_label: Label = $Numbers/Current
@onready var target_label: Label = $Numbers/Target
@onready var bar: ProgressBar = $Track/Bar
@onready var glow: ColorRect = $Track/Glow
@onready var motes: Node2D = $Motes
var context: String = ""
var displayed_value: float = 0.0
var low_effects: bool = false
var speed: float = 1.0
var _arrived_value: int = 0
var _target_value: int = 0
var _fill_tween: Tween
var _glow_tween: Tween
var _epoch: int = 0
var _material: ShaderMaterial

func _ready() -> void:
	_material = glow.material.duplicate() as ShaderMaterial
	glow.material = _material
	_material.set_shader_parameter("intensity", 0.0)
	bar.item_rect_changed.connect(_update_glow_edge)

func _exit_tree() -> void:
	cancel()

## 参数来自规则的只读投影；上下文改变立即取消旧局/旧目标的装饰。
func show_goal(key: String, value: int, minimum: int, maximum: int, current_tip: String, target_tip: String, rule_tip: String) -> void:
	var changed: bool = context != key
	if changed:
		if is_animating(): cancel()
		else: _clear_glow()
		context = key
	bar.min_value = minimum
	bar.max_value = maxi(minimum + 1, maximum)
	target_label.text = str(maximum)
	current_label.tooltip_text = current_tip
	target_label.tooltip_text = target_tip
	bar.tooltip_text = rule_tip
	if changed or not is_animating():
		_target_value = value
		_arrived_value = value
		_set_value(float(value))

func add_gain(amount: int, origin: Vector2) -> void:
	if context.is_empty(): return
	_target_value += maxi(0, amount)
	if low_effects:
		_arrived_value += maxi(0, amount)
		_animate_fill()
		return
	if motes.get_child_count() >= config.maximum_motes:
		(motes.get_child(motes.get_child_count() - 1) as ScoreMote).gain += maxi(0, amount)
		return
	var mote: ScoreMote = MOTE.instantiate() as ScoreMote
	motes.add_child(mote)
	mote.arrived.connect(_arrived.bind(mote))
	var inverse: Transform2D = motes.get_global_transform_with_canvas().affine_inverse()
	mote.play(inverse * origin, inverse * endpoint(), maxi(0, amount), config.mote_color, config.flight_duration, config.arc_height, speed)

func endpoint() -> Vector2:
	var fraction: float = clampf((bar.value - bar.min_value) / maxf(1.0, bar.max_value - bar.min_value), 0.0, 1.0)
	return bar.get_global_transform_with_canvas() * Vector2(clampf(bar.size.x * fraction, 4.0, maxf(4.0, bar.size.x - 4.0)), bar.size.y * 0.5)

func accepted_value() -> int:
	return _target_value

func is_animating() -> bool:
	return motes.get_child_count() > 0 or (_fill_tween != null and _fill_tween.is_valid() and _fill_tween.is_running())

func wait_until_settled() -> bool:
	var epoch: int = _epoch
	while is_animating():
		await animation_changed
		if epoch != _epoch: return false
	return true

func finish_now() -> bool:
	var active: bool = is_animating()
	_clear_motes()
	if _fill_tween != null and _fill_tween.is_valid(): _fill_tween.kill()
	_arrived_value = _target_value
	_set_value(float(_target_value))
	_clear_glow()
	animation_changed.emit()
	return active

func cancel() -> void:
	_epoch += 1
	_clear_motes()
	if _fill_tween != null and _fill_tween.is_valid(): _fill_tween.kill()
	_clear_glow()
	animation_changed.emit()

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	if enabled: finish_now()

func set_speed(value: float) -> void:
	speed = maxf(value, 0.01)
	if _fill_tween != null and _fill_tween.is_valid(): _fill_tween.set_speed_scale(speed)
	if _glow_tween != null and _glow_tween.is_valid(): _glow_tween.set_speed_scale(speed)
	for child: Node in motes.get_children(): (child as ScoreMote).set_speed(speed)

func _arrived(amount: int, mote: ScoreMote) -> void:
	motes.remove_child(mote)
	_arrived_value += amount
	_animate_fill()
	_pulse()
	animation_changed.emit()

func _animate_fill() -> void:
	if _fill_tween != null and _fill_tween.is_valid(): _fill_tween.kill()
	_fill_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_speed_scale(speed)
	_fill_tween.tween_method(_set_value, displayed_value, float(_arrived_value), config.fill_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fill_tween.finished.connect(_finish_fill)

## 先关闭显示屏障再唤醒所有等待者；合法目标切换不取消同批其他等待。
func _finish_fill() -> void:
	_fill_tween = null
	animation_changed.emit()

func _set_value(value: float) -> void:
	displayed_value = value
	bar.value = value
	current_label.text = str(roundi(value))
	value_changed.emit(roundi(value))
	_update_glow_edge()

func _update_glow_edge() -> void:
	if _material == null: return
	_material.set_shader_parameter("canvas_size", glow.size)
	var fraction: float = clampf((bar.value - bar.min_value) / maxf(1.0, bar.max_value - bar.min_value), 0.0, 1.0)
	_material.set_shader_parameter("edge", clampf(fraction, 4.0 / maxf(8.0, bar.size.x), 1.0 - 4.0 / maxf(8.0, bar.size.x)))

func _pulse() -> void:
	if low_effects: return
	if _glow_tween != null and _glow_tween.is_valid(): _glow_tween.kill()
	_material.set_shader_parameter("intensity", 1.0)
	_glow_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_speed_scale(speed)
	_glow_tween.tween_method(func(value: float) -> void: _material.set_shader_parameter("intensity", value), 1.0, 0.0, config.glow_duration)

func _clear_glow() -> void:
	if _glow_tween != null and _glow_tween.is_valid(): _glow_tween.kill()
	if _material != null: _material.set_shader_parameter("intensity", 0.0)

func _clear_motes() -> void:
	if not is_instance_valid(motes): return
	for child: Node in motes.get_children():
		(child as ScoreMote).cancel()
		motes.remove_child(child)
		child.queue_free()
