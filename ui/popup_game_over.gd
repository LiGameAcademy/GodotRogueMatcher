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

func _on_btn_quit_pressed() -> void:
	quit_game.emit()

func _on_btn_retry_pressed() -> void:
	retry_game.emit()
