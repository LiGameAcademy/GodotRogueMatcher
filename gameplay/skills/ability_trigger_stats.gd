class_name AbilityTriggerStats
extends RefCounted

## Counts RuleResult.activations for author-facing trigger stats.
## Used = consumed=true. Attempt = matched complete OR in-scope condition/limit reject.
## owner_mismatch / event_type_mismatch are never attempts and must not inflate the denominator.

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
	return _count_for_skill(records, skill_id, true)

## In-scope attempt count (matches + condition/limit rejects) for one skill_id.
static func attempts_for_skill(records: Array[Dictionary], skill_id: StringName) -> int:
	return _count_for_skill(records, skill_id, false)

## Per-skill consumed totals; keys are skill_id strings.
static func consumed_by_skill(records: Array[Dictionary]) -> Dictionary[String, int]:
	return _totals_by_skill(records, true)

## Per-skill attempt totals; keys are skill_id strings.
static func attempts_by_skill(records: Array[Dictionary]) -> Dictionary[String, int]:
	return _totals_by_skill(records, false)

## consumed/attempts; null when attempts==0 so zero score is not "proven unused".
static func consume_rate_for_skill(records: Array[Dictionary], skill_id: StringName) -> Variant:
	var attempts: int = attempts_for_skill(records, skill_id)
	if attempts <= 0:
		return null
	return float(consumed_for_skill(records, skill_id)) / float(attempts)

static func _count_for_skill(records: Array[Dictionary], skill_id: StringName, consumed_only: bool) -> int:
	var wanted: String = String(skill_id)
	if wanted.is_empty():
		return 0
	var instances: Dictionary[String, String] = skill_instance_map(records)
	var total: int = 0
	for activation: Dictionary in _activations(records):
		if instances.get(str(activation.get("skill_instance_id", "")), "") != wanted:
			continue
		if consumed_only:
			if bool(activation.get("consumed", false)):
				total += 1
		elif _is_attempt(activation):
			total += 1
	return total

static func _totals_by_skill(records: Array[Dictionary], consumed_only: bool) -> Dictionary[String, int]:
	var instances: Dictionary[String, String] = skill_instance_map(records)
	var totals: Dictionary[String, int] = {}
	for activation: Dictionary in _activations(records):
		if consumed_only and not bool(activation.get("consumed", false)):
			continue
		if not consumed_only and not _is_attempt(activation):
			continue
		var skill_id: String = instances.get(str(activation.get("skill_instance_id", "")), "")
		if skill_id.is_empty():
			continue
		totals[skill_id] = int(totals.get(skill_id, 0)) + 1
	return totals

static func _activations(records: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in records:
		if row.get("kind") != "RuleResult":
			continue
		var activations: Variant = row.get("activations", [])
		if not activations is Array:
			continue
		for entry: Variant in activations:
			if entry is Dictionary:
				result.append(entry)
	return result

static func _is_attempt(activation: Dictionary) -> bool:
	if bool(activation.get("attempt", false)):
		return true
	if bool(activation.get("matched", false)):
		return true
	var reason: String = String(activation.get("reason", ""))
	return reason == "condition_rejected" or reason == "trigger_limit_reached"

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
