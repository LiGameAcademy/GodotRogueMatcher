extends UIForm
class_name MenuForm

#signal btn_new_game_pressed
#signal btn_settings_pressed
#signal btn_rank_pressed
#signal btn_quit_pressed

const signal_new_game : StringName = "menu_form_new_game"
const signal_quit_game : StringName = "menu_form_quit_game"

@onready var margin_container: MarginContainer = %MarginContainer
#@onready var w_settings_popup: MarginContainer = %w_settings_popup
#@onready var w_rank_popup: MarginContainer = %w_rank_popup

func _on_btn_new_game_pressed() -> void:
	ui_manager.emit(signal_new_game, [])

func _on_btn_settings_pressed() -> void:
	ui_manager.open_interface("popup_settings")
#	btn_settings_pressed.emit()

func _on_btn_rank_pressed() -> void:
	var w_rank_popup = ui_manager.open_interface("popup_rank")
#	btn_rank_pressed.emit()
	w_rank_popup.update_rank_board()

func _on_btn_quit_pressed() -> void:
#	btn_quit_pressed.emit()
	ui_manager.emit(signal_quit_game, [])

#func _on_w_settings_popup_confirm_pressed() -> void:
#	margin_container.show()
#	w_settings_popup.hide()
#
#func _on_w_rank_popup_btn_confirm_pressed() -> void:
#	margin_container.show()
#	w_rank_popup.hide()
