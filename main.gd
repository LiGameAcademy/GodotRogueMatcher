extends Node2D

func _enter_tree() -> void:
	var game: Node = $Game
	var primary: bool = get_parent() == get_tree().root and DisplayServer.get_name() != "headless"
	game.set("collection_context", ("web_playtest" if OS.has_feature("web") else "desktop_playtest" if OS.has_feature("template") else "editor_playtest") if primary else "automated_integration")
	if OS.has_feature("web"): game.set("record_runs", false)
	game.set("intercept_window_close", primary)
	game.set("enable_checkpoints", primary)
	if primary: game.set("show_start_menu", true)
