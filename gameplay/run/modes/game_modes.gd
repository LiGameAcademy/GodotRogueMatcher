class_name GameModes
extends RefCounted

const CLASSIC: GameModeDefinition = preload("res://gameplay/run/modes/classic_endless.tres")
const CHALLENGE: GameModeDefinition = preload("res://gameplay/run/modes/stage_challenge.tres")
const ALL: Array[GameModeDefinition] = [CLASSIC, CHALLENGE]

static func find(mode_id: StringName) -> GameModeDefinition:
	for mode: GameModeDefinition in ALL:
		if mode.mode_id == mode_id: return mode
	return null
