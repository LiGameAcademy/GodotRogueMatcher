class_name PieceAura
extends Node2D

const CONFIG: BoardJuiceConfig = preload("res://gameplay/presentation/board_juice_config.tres")
var _color: Color = Color.WHITE
var _selected: bool = false
var _energy: float = 0.0
var _pulse: Tween

func show_selection(color: Color, selected: bool, low_effects: bool) -> void:
	_color = color
	_selected = selected
	if _pulse != null and _pulse.is_valid(): _pulse.kill()
	_energy = 0.0
	if selected and not low_effects:
		_pulse = create_tween().set_loops()
		_pulse.tween_method(_set_energy, 0.0, 1.0, CONFIG.pulse_seconds).set_trans(Tween.TRANS_SINE)
		_pulse.tween_method(_set_energy, 1.0, 0.0, CONFIG.pulse_seconds).set_trans(Tween.TRANS_SINE)
	queue_redraw()

func _set_energy(value: float) -> void:
	_energy = value
	queue_redraw()

func _draw() -> void:
	if not _selected: return
	var radius: float = CONFIG.selection_radius + _energy
	draw_circle(Vector2.ZERO, radius, Color(_color, 0.55 + _energy * 0.25), false, 1.4, true)
	for quadrant: int in range(4):
		var angle: float = quadrant * PI / 2.0
		draw_arc(Vector2.ZERO, radius + 3.0, angle - 0.12, angle + 0.12, 8, Color.WHITE, 1.5, true)
