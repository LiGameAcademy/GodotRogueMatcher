extends UIPopup
class_name PopupNameInput

@onready var te_name: TextEdit = %te_name
@onready var btn_quit: TextureButton = %btn_quit
@onready var btn_confirm: TextureButton = %btn_confirm

#signal btn_quit_pressed
#signal btn_confirm_pressed(player_name : String)
const signal_confirm = "popup_name_input_confirm"
const signal_quit = "popup_name_input_quit"

func _ready() -> void:
	btn_quit.pressed.connect(_on_btn_quit_pressed)
	btn_confirm.pressed.connect(_on_btn_confirm_pressed)

func _on_btn_quit_pressed() -> void:
	ui_manager.emit(signal_quit, [])

func _on_btn_confirm_pressed() -> void:
	if te_name.text.is_empty():
		print_debug("没有输入玩家名，无法提交")
		return
	ui_manager.emit(signal_confirm, [te_name.text])
