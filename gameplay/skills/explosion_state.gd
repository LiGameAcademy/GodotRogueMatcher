class_name ExplosionState
extends RefCounted

var unlocked: bool = false
var radius_level: int = 0
var reward_level: int = 0
var blast_extra_level: int = 0
var match_extra_level: int = 0
var multiplier_level: int = 0
var instances: Dictionary[int, AbilityInstance] = {}
var upgrades: Dictionary[StringName, int] = {}
var core_pool_unlocked: bool = false
var fuse_unlocked: bool = false
var actions: Dictionary[int, DemolitionActionState] = {}

func level(upgrade: StringName) -> int:
	return upgrades.get(upgrade, 0)
