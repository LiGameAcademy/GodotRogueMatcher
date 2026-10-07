class_name BoardJuiceConfig
extends Resource

## 只读表现参数，不影响生成、占格或计分。
@export var piece_colors: Array[Color] = [Color("ff6474"), Color("73e3ae"), Color("75adff"), Color("ffd86e"), Color("d69aff")]
@export var path_color: Color = Color("74ddcf")
@export var selection_radius: float = 26.0
@export var selected_scale: float = 1.08
@export var pulse_seconds: float = 0.55
@export var elimination_seconds: float = 0.2
@export var anticipation_ratio: float = 0.25
@export var blast_seconds: float = 0.38
@export var blast_color: Color = Color("ffbf75")
