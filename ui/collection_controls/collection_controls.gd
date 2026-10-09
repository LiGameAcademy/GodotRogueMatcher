class_name CollectionControls
extends VBoxContainer

signal folder_requested
signal export_requested
signal quit_requested

@onready var status: Label = $Status
@onready var folder: Button = $Buttons/Folder
@onready var export_button: Button = $Buttons/Export
@onready var quit_button: Button = $Buttons/Quit

func _ready() -> void:
	folder.pressed.connect(folder_requested.emit)
	export_button.pressed.connect(export_requested.emit)
	quit_button.pressed.connect(quit_requested.emit)

func show_status(message: String, enabled: bool, can_quit: bool) -> void:
	visible = enabled and not OS.has_feature("web")
	status.text = tr(message)
	folder.disabled = not enabled
	export_button.disabled = not enabled
	quit_button.visible = can_quit
