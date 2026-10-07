class_name ExplosionVisual
extends Node2D

var _area: Rect2
var low_effects: bool = false
const CONFIG: BoardJuiceConfig = preload("res://gameplay/presentation/board_juice_config.tres")
var _progress: float = 0.0
var _generation: int = 0

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	queue_redraw()

func setup(area: Rect2, generation: int = 0) -> Tween:
	_area = area
	_generation = generation
	queue_redraw()
	var tween: Tween = create_tween()
	tween.set_parallel()
	tween.tween_method(_set_progress, 0.0, 1.0, CONFIG.blast_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, CONFIG.blast_seconds)
	tween.finished.connect(queue_free)
	return tween

func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()

func _draw() -> void:
	var color: Color = CONFIG.blast_color
	if not low_effects:
		draw_rect(_area, Color(color, 0.10 * (1.0 - _progress)), true)
		var radius: float = lerpf(18.0, _area.size.length() * 0.5, _progress)
		var wave: PackedVector2Array = PackedVector2Array()
		for index: int in range(49):
			var point: Vector2 = Vector2.from_angle(index * TAU / 48.0) * radius
			point = point.clamp(_area.position, _area.end)
			wave.append(point)
		draw_polyline(wave, Color(color, 0.8), 2.0, true)
	draw_rect(_area, color, false, 2.0)
	var text: String = "爆破" if _generation <= 1 else "连锁 · 第%d波" % _generation
	draw_string(ThemeDB.fallback_font, _area.position + Vector2(6, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
