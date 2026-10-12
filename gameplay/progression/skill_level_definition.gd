class_name SkillLevelDefinition
extends Resource

## Per-level read-only config. One acquire ability root; the root may be a leaf or CompositeEffect.
@export var level: int = 1
@export var abilities: Array[AbilityDefinition] = []

## Validate this level; return an English diagnostic on failure, or an empty string when valid.
func validation_error() -> String:
	if level < 1 or abilities.size() != 1: return "this slice requires exactly one acquire ability per level"
	var ability: AbilityDefinition = abilities[0]
	if ability == null or ability.ability_id.is_empty(): return "ability id missing"
	var error: String = AbilityTriggerAdapter.validation_error(ability)
	if not error.is_empty(): return error
	if not ability.conditions.is_empty() or ability.max_triggers != 0:
		return "acquire conditions and limits remain owned by choice preflight"
	var expected: StringName = &"skill_acquired" if level == 1 else &"skill_upgraded"
	if ability.event_type != expected: return "acquire/upgrade event timing does not match level"
	if ability.effect is ChoiceEffect or ability.effect is CompositeEffect: return ""
	return "acquire ability requires choice or composite effect"
