extends Control
class_name PopupGameOver

## 游戏结束弹窗

signal quit_game
signal retry_game

@onready var btn_quit: TextureButton = %btn_quit
@onready var btn_retry: TextureButton = %btn_retry

func _ready() -> void:
	btn_quit.pressed.connect(_on_btn_quit_pressed)
	btn_retry.pressed.connect(_on_btn_retry_pressed)

## 初始化弹窗（统一接口，符合开闭原则）
## [param data: Dictionary] 初始化数据（可选）
func initialize(data: Dictionary = {}) -> void:
	# PopupGameOver 不需要额外初始化数据
	pass

func _on_btn_quit_pressed() -> void:
	quit_game.emit()

func _on_btn_retry_pressed() -> void:
	retry_game.emit()
