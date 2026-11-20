class_name SkillOfferTraits
extends Resource

## Read-only acquisition semantics, independent of display tags and execution state.
const ROUTES: Array[StringName] = [&"blast", &"fuse", &"line", &"dye", &"shape", &"palette"]
const CAPABILITIES: Array[StringName] = [&"core_supply", &"fuse_unlocked", &"live_fuse", &"line_supply", &"row_supply", &"column_supply", &"dye_engine"]
const ROLES: Array[StringName] = [&"supply", &"payoff", &"enhancement", &"instant", &"generic", &"shape_unlock", &"bridge"]

@export var mechanisms: Array[StringName] = []
@export var affinity: Array[StringName] = []
@export var invests: Array[StringName] = []
@export var supplies: Array[StringName] = []
@export var payoffs: Array[StringName] = []
@export var needs: Array[StringName] = []
@export var roles: Array[StringName] = []
@export_enum("persistent", "finite", "instant") var lifetime: String = "persistent"
@export var once_per_run: bool = true
@export var upgradeable: bool = false
@export var repeatable: bool = false
@export var utility_pick: bool = false
@export var exception_multiplier: float = 1.0

func validation_error() -> String:
	if lifetime not in ["persistent", "finite", "instant"]: return "unknown skill lifetime"
	if int(once_per_run) + int(upgradeable) + int(repeatable) != 1:
		return "exactly one acquisition policy is required"
	if not is_finite(exception_multiplier) or exception_multiplier <= 0.0:
		return "offer exception multiplier must be positive"
	for field: String in ["mechanisms", "affinity", "invests", "supplies", "payoffs", "needs", "roles"]:
		var values: Array[StringName] = get(field)
		var allowed: Array[StringName] = CAPABILITIES if field == "needs" else (ROLES if field == "roles" else ROUTES)
		var seen: Array[StringName] = []
		for value: StringName in values:
			if not allowed.has(value) or seen.has(value): return "unknown or duplicate offer trait: " + field
			seen.append(value)
	if roles.is_empty(): return "offer role must be explicitly declared"
	if roles.has(&"shape_unlock") and (not affinity.is_empty() or not supplies.is_empty() or not payoffs.is_empty()):
		return "shape unlocks cannot claim affinity or a mechanism gap"
	return ""
