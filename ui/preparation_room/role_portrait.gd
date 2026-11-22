extends TextureRect

## Displays the same character illustration wherever a run identity is shown.
const ROLE: Script = preload("res://gameplay/openings/opening_role.gd")

func display(role: ROLE) -> void:
	texture = role.portrait
	tooltip_text = tr("role." + str(role.id))
	accessibility_name = tooltip_text
