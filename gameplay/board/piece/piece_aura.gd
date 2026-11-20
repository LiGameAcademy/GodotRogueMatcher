class_name PieceAura
extends Node2D

@export var config: PieceMarkerConfig = preload("res://gameplay/board/piece/piece_marker_config.tres")
@onready var corners: Array[TextureRect] = [$TopLeft, $TopRight, $BottomRight, $BottomLeft]
var _selected: bool = false
var _energy: float = 0.0
var _pulse: Tween

func show_selection(_color: Color, selected: bool, low_effects: bool) -> void:
	_selected = selected
	visible = selected
	if _pulse != null and _pulse.is_valid(): _pulse.kill()
	_set_energy(0.0)
	if selected and not low_effects:
		_pulse = create_tween().set_loops()
		_pulse.tween_method(_set_energy, 0.0, 1.0, config.pulse_seconds * 0.5).set_trans(Tween.TRANS_SINE)
		_pulse.tween_method(_set_energy, 1.0, 0.0, config.pulse_seconds * 0.5).set_trans(Tween.TRANS_SINE)

func _set_energy(value: float) -> void:
	_energy = value
	var extent: float = config.corner_extent + value * config.corner_travel
	var directions: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for index: int in range(corners.size()):
		var corner: TextureRect = corners[index]
		corner.size = Vector2.ONE * config.corner_size
		corner.pivot_offset = corner.size * 0.5
		corner.position = directions[index] * (extent - config.corner_size * 0.5) - corner.size * 0.5
		corner.modulate.a = 0.86 + value * 0.14
