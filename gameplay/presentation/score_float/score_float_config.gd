class_name ScoreFloatConfig
extends Resource

## 只读显示参数；分档只影响提示，不改变规则收益。
@export var high_score: int = 100
@export var huge_score: int = 250
@export var normal_color: Color = Color("edf5ff")
@export var high_color: Color = Color("ffd86e")
@export var huge_color: Color = Color("ff9b72")
@export var extra_color: Color = Color("8de9d5")
@export var normal_font_size: int = 20
@export var extra_font_size: int = 16
@export var high_font_size: int = 26
@export var huge_font_size: int = 32
@export var high_peak_scale: float = 1.3
@export var huge_peak_scale: float = 1.5
@export var pop_seconds: float = 0.09
@export var settle_seconds: float = 0.18
@export var reveal_delay: float = 0.16
@export var hold_seconds: float = 0.35
@export var high_hold_seconds: float = 0.65
@export var fade_seconds: float = 0.75
@export var rise_distance: float = 22.0
@export var maximum_visible: int = 6
