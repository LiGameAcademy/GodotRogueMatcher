extends Resource

## Immutable starting loadout and presentation shared by the room, rules and restore.
@export var id: StringName
@export var threshold: int
@export var portrait: Texture2D
@export var skills: Array[SkillDefinition] = []
