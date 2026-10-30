class_name CollectionControls
extends VBoxContainer

signal folder_requested
signal export_requested
signal quit_requested
var _collection: RunCollection

@onready var status: Label = $Status
@onready var folder: Button = $Buttons/Folder
@onready var export_button: Button = $Buttons/Export
@onready var quit_button: Button = $Buttons/Quit

func _ready() -> void:
	folder.pressed.connect(folder_requested.emit)
	export_button.pressed.connect(export_requested.emit)
	quit_button.pressed.connect(quit_requested.emit)

func show_status(message: String, enabled: bool, can_quit: bool) -> void:
	visible = enabled
	status.text = tr(message)
	folder.disabled = not enabled
	folder.visible = not OS.has_feature("web")
	export_button.disabled = not enabled
	export_button.text = tr(_collection.export_label()) if _collection != null else tr("导出记录")
	quit_button.visible = can_quit and not OS.has_feature("web")

func bind_collection(collection: RunCollection, request_quit: Callable, can_quit: bool) -> void:
	_collection = collection
	folder_requested.connect(collection.open_directory)
	export_requested.connect(collection.export_files)
	quit_requested.connect(request_quit)
	show_status(collection.save_status(), collection.enabled, can_quit)
