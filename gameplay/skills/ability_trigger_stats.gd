class_name AbilityTriggerStats
extends RefCounted

## Counts completed ability activations from RuleResult.activations for author-facing trigger stats.
## "Used" means a matched activation finished with consumed=true (elimination/连携 fired), not merely installed.

## Maps skill_instance_id string → skill_id string from any snapshot that carries skills[].
static func skill_instance_map(records: Array[Dictionary]) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for row: Dictionary in records:
		_absorb_skills(result, row.get("state", {}).get("skills", []))
		_absorb_skills(result, row.get("after", {}).get("skills", []))
		_absorb_skills(result, row.get("final", {}).get("skills", []))
	return result

## Consumed activation count for one skill_id across the whole record.
static func consumed_for_skill(records: Array[Dictionary], skill_id: StringName) -> int:
	var wanted: String = String(skill_id)
	if wanted.is_empty():
		return 0
	var instances: Dictionary[String, String] = skill_instance_map(records)
	var total: int = 0
	for row: Dictionary in records:
		if row.get("kind") != "RuleResult":
			continue
		var activations: Variant = row.get("activations", [])
		if not activations is Array:
			continue
		for entry: Variant in activations:
			if not entry is Dictionary:
				continue
			var activation: Dictionary = entry
			if not bool(activation.get("consumed", false)):
				continue
			var instance_key: String = str(activation.get("skill_instance_id", ""))
			if instances.get(instance_key, "") == wanted:
				total += 1
	return total

## Per-skill consumed totals; keys are skill_id strings.
static func consumed_by_skill(records: Array[Dictionary]) -> Dictionary[String, int]:
	var instances: Dictionary[String, String] = skill_instance_map(records)
	var totals: Dictionary[String, int] = {}
	for row: Dictionary in records:
		if row.get("kind") != "RuleResult":
			continue
		var activations: Variant = row.get("activations", [])
		if not activations is Array:
			continue
		for entry: Variant in activations:
			if not entry is Dictionary:
				continue
			var activation: Dictionary = entry
			if not bool(activation.get("consumed", false)):
				continue
			var skill_id: String = instances.get(str(activation.get("skill_instance_id", "")), "")
			if skill_id.is_empty():
				continue
			totals[skill_id] = int(totals.get(skill_id, 0)) + 1
	return totals

static func _absorb_skills(into: Dictionary[String, String], skills: Variant) -> void:
	if not skills is Array:
		return
	for entry: Variant in skills:
		if not entry is Dictionary:
			continue
		var skill: Dictionary = entry
		if not skill.has("instance_id") or not skill.has("skill_id"):
			continue
		into[str(skill.instance_id)] = String(skill.skill_id)
