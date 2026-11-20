extends Node

## Opens the real release menu and settings with disposable local preferences.
const OUTPUT: String = "res://.godot/issue130-ui-motion/captures"
@onready var _game: Node2D = $Game

func _ready() -> void:
	get_window().title = "技能连珠 · UI 动画验收（#130）"
	if "--capture-ui" in OS.get_cmdline_user_args():
		await _capture_views()

func _capture_views() -> void:
	var board: Board = _game.get_node("Board") as Board
	while not board.can_selected or not (_game.get("release_menu") as ReleaseMenu).visible:
		await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _capture("menu")
	var settings: PlaybackSettings = _game.get_node("PlaybackSettings") as PlaybackSettings
	settings.open(false, false)
	await get_tree().create_timer(0.25, true).timeout
	await _capture("settings")
	settings.close()
	get_tree().quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))
	if error != OK: push_error(error_string(error))
