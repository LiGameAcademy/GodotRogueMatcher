class_name AbilityTriggerAdapter
extends RefCounted

const MAX_CONDITION_DEPTH: int = 8

const EVENTS: Array[StringName] = [&"piece_eliminated", &"skill_acquired", &"skill_upgraded"]
const CAUSES: Array[StringName] = [&"match", &"explosion", &"skill_clear", &"consume"]

## Reuse plugin read-only conditions only; do not activate shared triggers or subscribe to a global bus.
static func validation_error(definition: AbilityDefinition) -> String:
	if definition == null or definition.ability_id.is_empty(): return "ability id missing"
	if not EVENTS.has(definition.event_type): return "ability event not supported"
	if definition.max_triggers < 0: return "ability trigger limit cannot be negative"
	if definition.event_type == AbilityEvent.PIECE_ELIMINATED:
		if not definition.effect is ExplodeEffect: return "removal ability requires explode effect"
	elif definition.effect is CompositeEffect:
		var composite_error: String = (definition.effect as CompositeEffect).validation_error()
		if not composite_error.is_empty(): return composite_error
	elif not definition.effect is ChoiceEffect:
		return "acquire ability requires choice or composite effect"
	for condition: TriggerCondition in definition.conditions:
		var error: String = _condition_error(condition, [])
		if not error.is_empty(): return error
	return ""

## Pure query; trigger counts are committed only by AbilityEvents.complete after application.
static func matches(instance: AbilityInstance, event: AbilityEvent) -> bool:
	return bool(explain(instance, event).get("matched", false))

## Deterministic condition walk for records/debug; short-circuits like matches().
static func explain(instance: AbilityInstance, event: AbilityEvent) -> Dictionary:
	var conditions: Array[Dictionary] = []
	var definition_error: String = validation_error(instance.definition)
	if not definition_error.is_empty():
		return {"matched": false, "reason": definition_error, "conditions": conditions}
	if event.source == null or instance.owner_id != event.source.piece_id:
		return {"matched": false, "reason": "owner_mismatch", "conditions": conditions}
	var definition: AbilityDefinition = instance.definition
	if definition.event_type != event.event_type:
		return {"matched": false, "reason": "event_type_mismatch", "conditions": conditions}
	if definition.max_triggers > 0 and instance.trigger_count >= definition.max_triggers:
		return {"matched": false, "reason": "trigger_limit_reached", "conditions": conditions}
	var context: Dictionary = event.to_context()
	for index: int in range(definition.conditions.size()):
		var accepted: bool = _evaluate(definition.conditions[index], context)
		conditions.append({"index": index, "result": accepted})
		if not accepted:
			return {"matched": false, "reason": "condition_rejected", "conditions": conditions}
	return {"matched": true, "reason": "", "conditions": conditions}

static func _condition_error(condition: TriggerCondition, ancestors: Array[TriggerCondition]) -> String:
	if condition == null: return "ability trigger condition missing"
	if ancestors.has(condition): return "ability trigger condition cycle"
	if ancestors.size() >= MAX_CONDITION_DEPTH: return "ability trigger condition nested too deep"
	if condition is CompositeTriggerCondition:
		var composite: CompositeTriggerCondition = condition as CompositeTriggerCondition
		if not ["AND", "OR", "NOR"].has(composite.operator): return "unsupported condition operator"
		if composite.conditions.is_empty(): return "composite condition missing children"
		if composite.operator == "NOR" and composite.conditions.size() != 1: return "negation condition requires one child"
		ancestors.append(condition)
		for child: TriggerCondition in composite.conditions:
			var error: String = _condition_error(child, ancestors)
			if not error.is_empty(): return error
		ancestors.pop_back()
	elif condition is RemovalCauseCondition:
		var causes: Array[StringName] = (condition as RemovalCauseCondition).allowed_causes
		if causes.is_empty(): return "removal cause condition missing causes"
		for cause: StringName in causes:
			if not CAUSES.has(cause): return "unsupported removal cause"
	elif condition is EventTypeTriggerCondition:
		if not EVENTS.has((condition as EventTypeTriggerCondition).event_type): return "condition event not supported"
	elif not condition is AlwaysAbilityCondition: return "unsupported trigger condition; probability is not wired to the run RNG protocol"
	return ""

## Short-circuit in configured order; reject unsupported plugin conditions to avoid timers or global RNG.
static func _evaluate(condition: TriggerCondition, context: Dictionary) -> bool:
	if condition is CompositeTriggerCondition:
		var composite: CompositeTriggerCondition = condition as CompositeTriggerCondition
		if composite.operator == "NOR": return not _evaluate(composite.conditions[0], context)
		for child: TriggerCondition in composite.conditions:
			var accepted: bool = _evaluate(child, context)
			if composite.operator == "AND" and not accepted: return false
			if composite.operator == "OR" and accepted: return true
		return composite.operator == "AND"
	return condition.evaluate(context)
