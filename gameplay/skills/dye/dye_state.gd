class_name DyeState
extends RefCounted

var upgrades: Dictionary[StringName, int] = {}
var marks: Dictionary[int, int] = {}
var root_id: int = -1
var waves_used: int = 0
var considered_match: bool = false
var considered_blast: bool = false
var allow_chain: bool = false
var dyed_ids: Array[int] = []

func level(id: StringName) -> int:
	return upgrades.get(id, 0)

func begin_root(id: int) -> void:
	if root_id == id: return
	root_id = id
	waves_used = 0
	considered_match = false
	considered_blast = false
	allow_chain = false
	dyed_ids.clear()

