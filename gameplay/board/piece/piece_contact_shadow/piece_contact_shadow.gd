extends Sprite2D

## Body-alpha contact shadow with an instance material and a cast direction from its cell.
const REST_DISTANCE: float = 8.0
const LIFT_DISTANCE: float = 13.0

var _shadow_material: ShaderMaterial
var _theme_offset: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.ZERO
var _lifted: bool = false

func _ready() -> void:
	_shadow_material = material.duplicate() as ShaderMaterial
	material = _shadow_material

## Requires a ready scene; body textures and theme configuration remain read-only.
func configure(body: Texture2D, appearance: BoardAppearance) -> void:
	texture = body
	scale = Vector2.ONE * NutVisual.BOARD_BODY_SIZE / body.get_width()
	_theme_offset = appearance.shadow_offset
	_shadow_material.set_shader_parameter("shadow_color", appearance.piece_shadow)
	visible = appearance.piece_shadow.a > 0.0
	_update_offset()

## Receives a unit cast vector from the cell. Standalone previews keep their theme offset.
func set_direction(direction: Vector2) -> void:
	_direction = direction
	_update_offset()

## Changes only the shadow reach when the player lifts or returns the piece.
func set_lifted(lifted: bool) -> void:
	_lifted = lifted
	_update_offset()

func _update_offset() -> void:
	if _direction == Vector2.ZERO:
		position = _theme_offset
	else:
		position = _direction * (LIFT_DISTANCE if _lifted else REST_DISTANCE)
