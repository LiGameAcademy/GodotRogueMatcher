extends Sprite2D

## Static body-alpha contact shadow; owns its material, never reads gameplay state.
var _shadow_material: ShaderMaterial

func _ready() -> void:
	_shadow_material = material.duplicate() as ShaderMaterial
	material = _shadow_material

## Requires a ready scene; body textures and theme configuration remain read-only.
func configure(body: Texture2D, appearance: BoardAppearance) -> void:
	texture = body
	scale = Vector2.ONE * 64.0 / body.get_width()
	position = appearance.shadow_offset
	_shadow_material.set_shader_parameter("shadow_color", appearance.piece_shadow)
	visible = appearance.piece_shadow.a > 0.0
