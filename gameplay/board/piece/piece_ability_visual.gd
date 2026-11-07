class_name PieceAbilityVisual
extends Node2D

## Draws local ability identity using the scene's pause-aware Tween clock.
@export var config: PieceMarkerConfig = preload("res://gameplay/board/piece/piece_marker_config.tres")
@onready var body_outline: Sprite2D = $BodyOutline
@onready var first_arrow: Sprite2D = $FirstArrow
@onready var second_arrow: Sprite2D = $SecondArrow
var kind: StringName = &""
var low_effects: bool = false
var energy: float = 0.0
var _outline: ShaderMaterial
var _pulse: Tween

func _ready() -> void:
	_outline = body_outline.material.duplicate() as ShaderMaterial
	body_outline.material = _outline
	_outline.set_shader_parameter("outline_width", config.outline_width)
	_outline.set_shader_parameter("outline_color", config.outline_color)
	_outline.set_shader_parameter("rim_width", config.outline_rim_width)
	_outline.set_shader_parameter("rim_color", config.outline_rim_color)
	for arrow: Sprite2D in [first_arrow, second_arrow]:
		arrow.scale = config.arrow_size / arrow.texture.get_size()

## 原始标记由父级传入；本组件不查规则、外部节点或翻译后的文字。
func configure(marker: StringName, body: Texture2D, reduced: bool) -> void:
	body_outline.texture = body
	body_outline.scale = Vector2.ONE * NutVisual.BOARD_BODY_SIZE / body.get_width()
	var changed: bool = kind != marker or low_effects != reduced
	kind = marker
	low_effects = reduced
	_outline.set_shader_parameter("fuse_mark", kind == &"引")
	_outline.set_shader_parameter("steady", reduced)
	body_outline.visible = kind in [&"爆", &"引"]
	first_arrow.visible = kind in [&"行", &"列"]
	second_arrow.visible = first_arrow.visible
	visible = body_outline.visible or first_arrow.visible
	if changed:
		if _pulse != null and _pulse.is_valid():
			_pulse.kill()
		_pulse = null
		_set_phase(0.0)
		if visible and not low_effects:
			_pulse = create_tween().set_loops()
			_pulse.tween_method(_set_phase, 0.0, 1.0, config.pulse_seconds)

func _set_phase(phase: float) -> void:
	energy = 0.5 - 0.5 * cos(phase * TAU)
	if body_outline.visible:
		_outline.set_shader_parameter("phase", phase)
		return
	if not first_arrow.visible:
		return
	var axis: Vector2 = Vector2.DOWN if kind == &"列" else Vector2.RIGHT
	first_arrow.position = axis * (config.arrow_offset + config.arrow_travel * energy)
	second_arrow.position = -first_arrow.position
	first_arrow.rotation = PI * 0.5 if kind == &"列" else 0.0
	second_arrow.rotation = first_arrow.rotation + PI
	for arrow: Sprite2D in [first_arrow, second_arrow]:
		arrow.modulate = Color(1.0 + energy * 0.12, 1.0 + energy * 0.12, 1.0 + energy * 0.12, 1)
