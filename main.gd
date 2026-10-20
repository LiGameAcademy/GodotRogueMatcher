extends Node2D

func _enter_tree() -> void:
	var game: Node = $Game
	var primary: bool = get_parent() == get_tree().root and DisplayServer.get_name() != "headless"
	game.set("collection_context", ("desktop_playtest" if OS.has_feature("template") else "editor_playtest") if primary else "automated_integration")
	game.set("intercept_window_close", primary)
