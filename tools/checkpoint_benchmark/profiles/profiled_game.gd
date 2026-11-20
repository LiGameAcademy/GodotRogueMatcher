extends "res://gameplay/game.gd"

## Runtime injection exists only in the probe; all game transitions still call super.
var profile: Dictionary = {}

func _enter_tree() -> void:
	collection_context = "automated_integration"

func _on_checkpoint_restored(active: RunController, fallback: bool) -> void:
	var started: int = Time.get_ticks_usec()
	super._on_checkpoint_restored(active, fallback)
	profile["restored_callback_usec"] = Time.get_ticks_usec() - started

func _apply_game_theme() -> void:
	var started: int = Time.get_ticks_usec()
	super._apply_game_theme()
	profile["theme_usec"] = Time.get_ticks_usec() - started

func _refresh_hud() -> void:
	var started: int = Time.get_ticks_usec()
	super._refresh_hud()
	profile["refresh_hud_usec"] = int(profile.get("refresh_hud_usec", 0)) + Time.get_ticks_usec() - started

func _suspend_collection() -> void:
	var started: int = Time.get_ticks_usec()
	super._suspend_collection()
	profile["suspend_collection_usec"] = Time.get_ticks_usec() - started
