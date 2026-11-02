class_name SkillTriggerPayoff
extends RefCounted

## Author-facing payoff modes for #88. Install≠use still holds, but most offer cards pay off at
## choose time via ChoiceEffect / skill_acquired, not via later RuleResult.activations.

const MODE_INSTALL_EFFECT: StringName = &"install_effect"
const MODE_MANUAL: StringName = &"manual"
const MODE_RECURRING: StringName = &"recurring"
const MODE_UNKNOWN: StringName = &"unknown"

## Classify a catalog definition. Manual wins over install; leveled acquire abilities that are not
## skill_acquired/skill_upgraded count as recurring.
static func mode_for_definition(skill: SkillDefinition) -> StringName:
	if skill == null:
		return MODE_UNKNOWN
	if skill.manual_use_limit > 0:
		return MODE_MANUAL
	if not skill.levels.is_empty():
		for level: SkillLevelDefinition in skill.levels:
			if level == null:
				return MODE_UNKNOWN
			for ability: AbilityDefinition in level.abilities:
				if ability == null:
					return MODE_UNKNOWN
				if ability.event_type != &"skill_acquired" and ability.event_type != &"skill_upgraded":
					return MODE_RECURRING
		return MODE_INSTALL_EFFECT
	if skill.choice_effect != null:
		return MODE_INSTALL_EFFECT
	return MODE_UNKNOWN

static func definition_for(skill_id: StringName) -> SkillDefinition:
	var wanted: String = String(skill_id)
	if wanted.is_empty():
		return null
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill != null and String(skill.skill_id) == wanted:
			return skill
	return null

static func mode_for_skill(skill_id: StringName) -> StringName:
	return mode_for_definition(definition_for(skill_id))

## Acquire/upgrade counters written by SkillInstance.commit_next_level into snapshot skills[].
## Instant choice_effect cards without levels stay 0 here; their payoff is the choose itself.
static func install_uses_for_skill(records: Array[Dictionary], skill_id: StringName) -> int:
	var wanted: String = String(skill_id)
	if wanted.is_empty():
		return 0
	var total: int = 0
	for row: Dictionary in records:
		for block_name: String in ["state", "after", "final"]:
			var block: Variant = row.get(block_name, {})
			if not block is Dictionary:
				continue
			var skills: Variant = (block as Dictionary).get("skills", [])
			if not skills is Array:
				continue
			for entry: Variant in skills:
				if not entry is Dictionary:
					continue
				var skill: Dictionary = entry
				if String(skill.get("skill_id", "")) != wanted:
					continue
				var abilities: Variant = skill.get("abilities", [])
				if not abilities is Array:
					continue
				for ability_entry: Variant in abilities:
					if not ability_entry is Dictionary:
						continue
					var ability: Dictionary = ability_entry
					var event_type: String = String(ability.get("event_type", ""))
					if event_type != "skill_acquired" and event_type != "skill_upgraded":
						continue
					total = maxi(total, int(ability.get("trigger_count", 0)))
	return total

## Empty when recurring attempts exist. Otherwise names why attempt=0 is not "failed to use".
static func window_missing_reason(records: Array[Dictionary], skill_id: StringName) -> String:
	if AbilityTriggerStats.attempts_for_skill(records, skill_id) > 0:
		return ""
	match mode_for_skill(skill_id):
		MODE_INSTALL_EFFECT:
			return "install_effect_not_recurring"
		MODE_MANUAL:
			return "manual_unused"
		MODE_RECURRING:
			return "no_in_scope_attempt"
		_:
			return "no_in_scope_attempt"
