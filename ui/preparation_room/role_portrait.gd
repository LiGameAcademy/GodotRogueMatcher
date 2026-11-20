extends TextureRect

const ROLE: Script = preload("res://gameplay/openings/opening_role.gd")
@onready var _insignia: TextureRect = $Insignia

func display(role: ROLE) -> void:
	texture = role.portrait
	_insignia.texture = role.badge
	_insignia.visible = role.badge != null
