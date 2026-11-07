class_name PieceMarkerConfig
extends Resource

## Read-only tuning for local markers. The values never affect rules or playback barriers.
@export var arrow_size: Vector2 = Vector2(8, 14)
@export var arrow_offset: float = 23.0
@export var arrow_travel: float = 2.0
@export var pulse_seconds: float = 2.0
## Texture offsets are expressed in a 64-pixel reference space.
@export var outline_width: float = 1.8
@export var outline_rim_width: float = 2.3
@export var outline_rim_color: Color = Color("40334e")
@export var outline_color: Color = Color("ffe28d")
@export var corner_size: float = 14.0
@export var corner_extent: float = 32.0
@export var corner_travel: float = 0.8
