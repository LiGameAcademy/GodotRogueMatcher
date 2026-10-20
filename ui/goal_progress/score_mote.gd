class_name ScoreMote
extends Node2D

signal arrived(gain: int)

var gain: int = 0
var color: Color = Color.WHITE
var _origin: Vector2
var _target: Vector2
var _control: Vector2
var _trail: PackedVector2Array = PackedVector2Array()
var _tween: Tween

func play(origin: Vector2, target: Vector2, amount: int, tint: Color, duration: float, arc_height: float, speed: float) -> void:
	gain = amount
	color = tint
	_origin = origin
	_target = target
	_control = (origin + target) * 0.5 + Vector2(-minf(absf(target.x - origin.x) * 0.18, arc_height), -arc_height)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_speed_scale(speed)
	_tween.tween_method(_sample, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_arrive)
	_sample(0.0)

func set_speed(speed: float) -> void:
	if _tween != null and _tween.is_valid(): _tween.set_speed_scale(speed)

func cancel() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()

func _exit_tree() -> void:
	cancel()

func _sample(progress: float) -> void:
	var inverse: float = 1.0 - progress
	position = inverse * inverse * _origin + 2.0 * inverse * progress * _control + progress * progress * _target
	_trail.append(position)
	if _trail.size() > 8: _trail.remove_at(0)
	queue_redraw()

func _arrive() -> void:
	arrived.emit(gain)
	queue_free()

func _draw() -> void:
	for index: int in range(_trail.size()):
		draw_circle(_trail[index] - position, 2.0, Color(color, 0.03 + 0.18 * index / maxi(1, _trail.size())))
	draw_circle(Vector2.ZERO, 9.0, Color(color, 0.06))
	draw_circle(Vector2.ZERO, 5.0, Color(color, 0.2))
	draw_circle(Vector2.ZERO, 2.6, color)
	draw_circle(Vector2.ZERO, 1.2, Color.WHITE)
