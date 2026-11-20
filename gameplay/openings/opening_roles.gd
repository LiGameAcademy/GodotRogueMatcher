extends RefCounted

const Role: Script = preload("res://gameplay/openings/opening_role.gd")
## Skill effects refer back to RunController. Load the roster on first use,
## once the scripts for that controller and its skill definitions are ready.
static var ALL: Array[Role]:
	get:
		if ALL.is_empty():
			for id: String in ["standard", "row_sweep", "dyer", "bomber"]:
				ALL.append(load("res://gameplay/openings/%s.tres" % id) as Role)
		return ALL

static func find(id: StringName) -> Role:
	for role: Role in ALL:
		if role.id == id: return role
	return null
