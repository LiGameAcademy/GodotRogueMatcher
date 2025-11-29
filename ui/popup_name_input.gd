extends Control
class_name PopupNameInput

## 名称输入弹窗

signal confirmed(player_name: String)
signal cancelled

@onready var te_name: TextEdit = %te_name
@onready var btn_quit: TextureButton = %btn_quit
@onready var btn_confirm: TextureButton = %btn_confirm

func _ready() -> void:
	btn_quit.pressed.connect(_on_btn_quit_pressed)
	btn_confirm.pressed.connect(_on_btn_confirm_pressed)

## 初始化弹窗（统一接口，符合开闭原则）
## [param data: Dictionary] 初始化数据（可选，可包含 "default_name" 键）
func initialize(data: Dictionary = {}) -> void:
	if "default_name" in data:
		te_name.text = data.default_name

func _on_btn_quit_pressed() -> void:
	cancelled.emit()
	hide()
	queue_free()

func _on_btn_confirm_pressed() -> void:
	if te_name.text.is_empty():
		print_debug("没有输入玩家名，无法提交")
		return
	confirmed.emit(te_name.text)
	hide()
	queue_free()
