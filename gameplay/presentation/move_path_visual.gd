class_name MovePathVisual
extends Node2D

const CONFIG: BoardJuiceConfig = preload("res://gameplay/presentation/board_juice_config.tres")
var _points: PackedVector2Array = PackedVector2Array()
var _reached: int = 0

func show_path(points: PackedVector2Array) -> void:
	_points = points.duplicate()
	_reached = 0
	queue_redraw()

func mark_reached(index: int) -> void:
	_reached = index
	queue_redraw()

func clear() -> void:
	_points.clear()
	queue_redraw()

func _draw() -> void:
	if _points.size() < 2: return
	draw_polyline(_points, Color(CONFIG.path_color, 0.3), 3.0, true)
	for index: int in range(1, _points.size()):
		var color: Color = Color(CONFIG.path_color, 0.8 if index <= _reached else 0.45)
		draw_circle(_points[index], 3.0, color, true, -1.0, true)
		var direction: Vector2 = (_points[index] - _points[index - 1]).normalized()
		var center: Vector2 = (_points[index] + _points[index - 1]) * 0.5
		draw_line(center - direction.rotated(0.55) * 6, center, color, 1.5, true)
		draw_line(center - direction.rotated(-0.55) * 6, center, color, 1.5, true)
	draw_circle(_points[-1], 13.0, CONFIG.path_color, false, 2.0, true)
