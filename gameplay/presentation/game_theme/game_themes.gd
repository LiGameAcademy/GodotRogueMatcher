class_name GameThemes
extends RefCounted

const ALL: Array[GameTheme] = [preload("res://gameplay/presentation/game_theme/light_toy.tres"), preload("res://gameplay/presentation/game_theme/dark_instrument.tres")]

static func find(theme_id: StringName) -> GameTheme:
	for preset: GameTheme in ALL:
		if preset.theme_id == theme_id: return preset
	return ALL[0]
