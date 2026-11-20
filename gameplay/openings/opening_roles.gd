extends RefCounted

const Role: Script = preload("res://gameplay/openings/opening_role.gd")
const ALL: Array[Role] = [preload("res://gameplay/openings/standard.tres"), preload("res://gameplay/openings/row_sweep.tres"), preload("res://gameplay/openings/dyer.tres"), preload("res://gameplay/openings/bomber.tres")]

static func find(id: StringName) -> Role:
	for role: Role in ALL:
		if role.id == id: return role
	return null
