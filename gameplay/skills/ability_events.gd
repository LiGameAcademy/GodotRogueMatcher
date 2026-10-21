class_name AbilityEvents
extends RefCounted

## Deterministic in-run dispatcher. Callers pass the authoritative listener set; no second registry.
var last_error: String = ""
var _scope: RefCounted = RefCounted.new()
var _next_id: int = 1
var _dispatched: Dictionary[int, bool] = {}
var _active: bool = true
## Per-command debug traces drained by RunRecorder into RuleResult.activations.
var _traces: Array[Dictionary] = []

## Freeze a removal source snapshot and assign a unique in-run event id.
func removal(source: PieceState, cause: StringName, root: int, generation: int, run_id: String = "", parent_id: int = 0, source_ability: StringName = &"") -> AbilityEvent:
	var event: AbilityEvent = AbilityEvent.new()
	event.event_id = _next_id
	_next_id += 1
	event.scope = _scope
	event.source = source.copy()
	event.cause = cause
	event.root_action_id = root
	event.generation = generation
	event.run_id = run_id
	event.parent_event_id = parent_id
	event.source_ability_id = source_ability
	return event

## After batch preflight, dispatch in stable generation/source/event and owner/install/ability order.
func dispatch(events: Array[AbilityEvent], listeners: Array[AbilityInstance]) -> Array[AbilityActivation]:
	last_error = ""
	if not _active: return []
	var identities: Dictionary[String, AbilityInstance] = {}
	for instance: AbilityInstance in listeners:
		if instance == null:
			last_error = "ability instance missing"
			return []
		last_error = AbilityTriggerAdapter.validation_error(instance.definition)
		if not last_error.is_empty(): return []
		var key: String = "%d/%d/%s" % [instance.owner_id, instance.skill_instance_id, instance.definition.ability_id]
		if identities.has(key) and identities[key] != instance:
			last_error = "duplicate ability instance identity"
			return []
		identities[key] = instance
	for event: AbilityEvent in events:
		if event == null or event.source == null:
			last_error = "event source snapshot missing"
			return []
	var ordered_events: Array[AbilityEvent] = events.duplicate()
	ordered_events.sort_custom(_event_before)
	var ordered_listeners: Array[AbilityInstance] = listeners.duplicate()
	ordered_listeners.sort_custom(_listener_before)
	var result: Array[AbilityActivation] = []
	for event: AbilityEvent in ordered_events:
		if event.scope != _scope or event.source == null or event.event_id <= 0 or event.event_id >= _next_id:
			continue
		if _dispatched.has(event.event_id): continue
		_dispatched[event.event_id] = true
		for instance: AbilityInstance in ordered_listeners:
			if instance.pending_event_id != 0: continue
			var explanation: Dictionary = AbilityTriggerAdapter.explain(instance, event)
			if not bool(explanation.get("matched", false)): continue
			var activation: AbilityActivation = AbilityActivation.new()
			activation.instance = instance
			activation.event = AbilityEvent.new()
			activation.event.event_id = event.event_id
			activation.event.scope = _scope
			activation.event.event_type = event.event_type
			activation.event.source = event.source.copy()
			activation.event.cause = event.cause
			activation.event.root_action_id = event.root_action_id
			activation.event.generation = event.generation
			activation.event.run_id = event.run_id
			activation.event.parent_event_id = event.parent_event_id
			activation.event.source_ability_id = event.source_ability_id
			activation.debug = explanation
			instance.pending_event_id = event.event_id
			result.append(activation)
	return result

## Rejected applications do not consume. Legal empty results follow definition policy. Duplicate or stale tickets are no-ops.
func complete(activation: AbilityActivation, applied: bool, affected_count: int) -> bool:
	if activation == null or activation.event == null or activation.instance == null or affected_count < 0:
		last_error = "invalid ability application result"
		return false
	if not _active or activation.completed or activation.event.scope != _scope: return false
	var instance: AbilityInstance = activation.instance
	if instance.pending_event_id != activation.event.event_id: return false
	instance.pending_event_id = 0
	activation.completed = true
	var consumed: bool = applied and (affected_count > 0 or instance.definition.consume_on_empty)
	if consumed:
		instance.trigger_count += 1
	_traces.append({
		"event_id": activation.event.event_id,
		"parent_event_id": activation.event.parent_event_id,
		"owner_id": instance.owner_id,
		"skill_instance_id": instance.skill_instance_id,
		"ability_id": instance.definition.ability_id,
		"source_ability_id": activation.event.source_ability_id,
		"cause": activation.event.cause,
		"generation": activation.event.generation,
		"matched": true,
		"reason": String(activation.debug.get("reason", "")),
		"conditions": activation.debug.get("conditions", []),
		"applied": applied,
		"affected_count": affected_count,
		"consumed": consumed,
		"consume_on_empty": instance.definition.consume_on_empty,
		"trigger_count_after": instance.trigger_count,
	})
	return applied

## Aborted descendants are recorded as interrupted, never as successful empty applications.
func cancel(activation: AbilityActivation, reason: StringName) -> void:
	if activation == null or activation.completed: return
	complete(activation, false, 0)
	if activation.completed:
		var trace: Dictionary = _traces.back()
		trace["interrupted"] = true
		trace["interruption_reason"] = reason

## Drain and clear per-command activation traces for RuleResult.activations.
func take_traces() -> Array[Dictionary]:
	var traces: Array[Dictionary] = _traces.duplicate(true)
	_traces.clear()
	return traces

## Close this run's dispatcher; old events and pending tickets become invalid.
func close() -> void:
	_active = false
	_dispatched.clear()
	_traces.clear()

## Export dedupe and id state for rule snapshots.
func data() -> Dictionary:
	var ids: Array[int] = []
	ids.assign(_dispatched.keys())
	ids.sort()
	return {"next_event_id": _next_id, "dispatched": ids, "active": _active}

func _event_before(a: AbilityEvent, b: AbilityEvent) -> bool:
	if a.generation != b.generation: return a.generation < b.generation
	if a.source.piece_id != b.source.piece_id: return a.source.piece_id < b.source.piece_id
	return a.event_id < b.event_id

func _listener_before(a: AbilityInstance, b: AbilityInstance) -> bool:
	if a.owner_id != b.owner_id: return a.owner_id < b.owner_id
	if a.skill_instance_id != b.skill_instance_id: return a.skill_instance_id < b.skill_instance_id
	return String(a.definition.ability_id) < String(b.definition.ability_id)
