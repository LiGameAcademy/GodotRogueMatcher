class_name BoardJuiceConfig
extends Resource

## Read-only presentation settings; never affect spawning, occupancy or scoring.
@export var piece_colors: Array[Color] = [Color("ff6474"), Color("73e3ae"), Color("75adff"), Color("ffd86e"), Color("d69aff")]
@export var path_color: Color = Color("74ddcf")
@export var selection_radius: float = 26.0
@export var selected_scale: float = 1.08
@export var pulse_seconds: float = 0.55
@export var elimination_seconds: float = 0.2
@export var anticipation_ratio: float = 0.25
@export var blast_seconds: float = 0.38
@export var blast_color: Color = Color("ffbf75")
@export var line_clear_seconds: float = 0.38
@export var line_clear_color: Color = Color("74ddcf")

## Local birth stretch and landing squash, applied only to the visual group.
@export var birth_stretch: Vector2 = Vector2(0.88, 1.12)
@export var landing_squash: Vector2 = Vector2(1.10, 0.94)
## Fraction of the existing birth clock used before the final local recovery.
@export_range(0.05, 0.95) var birth_landing_ratio: float = 0.65
## Reuses the existing landing budget, in seconds; no extra tail is appended.
@export var landing_seconds: float = 0.06
