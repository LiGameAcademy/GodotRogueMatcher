class_name BoardAppearance
extends Resource

## Read-only palette and surface parameters; views own mutable shader instances.
@export var piece_colors: Array[Color] = [Color("ff6474"), Color("73e3ae"), Color("75adff"), Color("ffd86e"), Color("d69aff")]
@export var cell_color: Color = Color("192128")
@export var cell_edge: Color = Color("27343e")
@export var hover_color: Color = Color("243740")
@export var selected_color: Color = Color("173b40")
@export var selection_edge: Color = Color("a1eee3")
@export var path_color: Color = Color("74ddcf")
@export var marker_color: Color = Color("ffffff")
@export var marker_background: Color = Color("14212d")
@export_range(0.0, 0.2) var cell_rounding: float = 0.01
@export_range(0.0, 1.0) var surface_strength: float = 0.15
@export var piece_shadow: Color = Color(0, 0, 0, 0.25)
@export var shadow_offset: Vector2 = Vector2(0, 1)
