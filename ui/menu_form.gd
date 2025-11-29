extends Control
class_name MenuForm

## 菜单表单

signal new_game
signal quit_game
signal open_settings
signal open_rank

@onready var margin_container: MarginContainer = %MarginContainer

func _on_btn_new_game_pressed() -> void:
	new_game.emit()

func _on_btn_settings_pressed() -> void:
	open_settings.emit()

func _on_btn_rank_pressed() -> void:
	open_rank.emit()

func _on_btn_quit_pressed() -> void:
	quit_game.emit()

#func _on_w_settings_popup_confirm_pressed() -> void:
#	margin_container.show()
#	w_settings_popup.hide()
#
#func _on_w_rank_popup_btn_confirm_pressed() -> void:
#	margin_container.show()
#	w_rank_popup.hide()
