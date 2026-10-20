class_name SkillEffect
extends Resource

## Read-only effect root. Leaves and CompositeEffect share this contract.
const MAX_EFFECT_DEPTH: int = 8

## Return an English diagnostic for illegal trees; empty string means valid.
func validation_error(_ancestors: Array[SkillEffect] = []) -> String:
	return ""
