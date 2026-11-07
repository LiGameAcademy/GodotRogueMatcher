class_name LineClearVisual
extends Node2D

## The view supplies a frozen board-space area; this scene never queries rule state.
@export var config: BoardJuiceConfig = preload("res://gameplay/presentation/board_juice_config.tres")
var low_effects: bool = false
var _area: Rect2
var _second_area: Rect2
var _axis: int = 0
var _progress: float = 0.0

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	queue_redraw()

func setup(area: Rect2, axis: int, second_area: Rect2 = Rect2()) -> Tween:
	_area = area
	_second_area = second_area
	_axis = axis
	queue_redraw()
	var animation: Tween = create_tween().set_parallel()
	animation.tween_method(_set_progress, 0.0, 1.0, config.line_clear_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(self, "modulate:a", 0.0, config.line_clear_seconds)
	animation.finished.connect(queue_free)
	return animation

## Projects a frozen sweep axis and radius into the visible board bounds.
static func board_area(bounds: Rect2, spacing: Vector2, dimensions: Vector2i, center: Vector2i, axis: int, radius: int) -> Rect2:
	var area: Rect2 = bounds
	var cell_size: Vector2 = bounds.size - Vector2(dimensions - Vector2i.ONE) * spacing
	if axis == LineClearState.AXIS_ROW:
		var minimum: int = maxi(0, center.y - maxi(0, radius))
		var maximum: int = mini(dimensions.y - 1, center.y + maxi(0, radius))
		area.position.y = minimum * spacing.y - cell_size.y * 0.5
		area.size.y = (maximum - minimum) * spacing.y + cell_size.y
	else:
		var minimum: int = maxi(0, center.x - maxi(0, radius))
		var maximum: int = mini(dimensions.x - 1, center.x + maxi(0, radius))
		area.position.x = minimum * spacing.x - cell_size.x * 0.5
		area.size.x = (maximum - minimum) * spacing.x + cell_size.x
	return area

func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()

func _draw() -> void:
	_draw_area(_area, _axis)
	if _second_area.has_area(): _draw_area(_second_area, 1 - _axis)

func _draw_area(area: Rect2, axis: int) -> void:
	var color: Color = config.line_clear_color
	draw_rect(area, Color(color, 0.45), false, 1.0)
	if low_effects: return
	draw_rect(area, Color(color, 0.08 * (1.0 - _progress)), true)
	var from: Vector2 = area.position
	var to: Vector2 = area.end
	if axis == LineClearState.AXIS_ROW:
		from.x = lerpf(area.position.x, area.end.x, _progress)
		to.x = from.x
	else:
		from.y = lerpf(area.position.y, area.end.y, _progress)
		to.y = from.y
	draw_line(from, to, Color(color, 0.15), 10.0, true)
	draw_line(from, to, color, 2.0, true)
