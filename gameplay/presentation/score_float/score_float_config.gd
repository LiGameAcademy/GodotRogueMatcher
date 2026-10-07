class_name ScoreFloatConfig
extends Resource

## 只读显示参数；分档只影响提示，不改变规则收益。
@export var high_score: int = 100
@export var huge_score: int = 250
@export var normal_color: Color = Color("edf5ff")
@export var high_color: Color = Color("ffd86e")
@export var huge_color: Color = Color("ff9b72")
@export var extra_color: Color = Color("8de9d5")
@export var reveal_delay: float = 0.16
@export var hold_seconds: float = 1.1
@export var fade_seconds: float = 0.4
@export var rise_distance: float = 28.0
@export var card_width: float = 230.0
@export var maximum_visible: int = 6
