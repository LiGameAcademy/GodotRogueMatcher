extends Resource

## Immutable starting loadout and presentation shared by the room, rules and restore.
@export var id: StringName
@export var threshold: int
@export var portrait: Texture2D
@export var skills: Array[SkillDefinition] = []

func starting_skill_text() -> String:
	var names: PackedStringArray = []
	for skill: SkillDefinition in skills: names.append(tr(skill.title))
	return tr("room.standard_skill") if names.is_empty() else " + ".join(names)
