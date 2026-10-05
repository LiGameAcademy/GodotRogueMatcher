class_name ExplosionVisual
extends Node2D

var _area: Rect2

func setup(area: Rect2) -> void:
	_area = area
	queue_redraw()
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.finished.connect(queue_free)

func _draw() -> void:
	draw_rect(_area, Color(1.0, 0.5, 0.1, 0.16), true)
	draw_rect(_area, Color(1.0, 0.65, 0.1), false, 3.0)
