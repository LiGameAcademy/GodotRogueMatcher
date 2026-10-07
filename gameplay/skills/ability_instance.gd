class_name AbilityInstance
extends RefCounted

var owner_id: int = 0
var definition: AbilityDefinition
var trigger_count: int = 0
var has_triggered: bool:
	get:
		return trigger_count > 0
