class_name PresentationConfig
extends Resource

@export var normal_speed: float = 1.0
@export var fast_speed: float = 2.0
@export var spawn_duration: float = 0.3
## 故障保护，不代替正常动画屏障；单步还保留预计时长的宽裕余量。
@export var step_timeout_seconds: float = 10.0
