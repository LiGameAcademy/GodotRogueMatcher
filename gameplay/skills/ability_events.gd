class_name AbilityEvents
extends RefCounted

## 本局确定性分发。订阅者由权威实例集合显式传入，不保存第二份注册表。
var last_error: String = ""
var _scope: RefCounted = RefCounted.new()
var _next_id: int = 1
var _dispatched: Dictionary[int, bool] = {}
var _active: bool = true

## 从离场棋子冻结来源快照，分配本局唯一事件编号。
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

## 批次预检后，按世代、来源编号、事件编号以及拥有者、安装序、能力标识稳定分发。
func dispatch(events: Array[AbilityEvent], listeners: Array[AbilityInstance]) -> Array[AbilityActivation]:
	last_error = ""
	if not _active: return []
	var identities: Dictionary[String, AbilityInstance] = {}
	for instance: AbilityInstance in listeners:
		if instance == null:
			last_error = "能力实例缺失"
			return []
		last_error = AbilityTriggerAdapter.validation_error(instance.definition)
		if not last_error.is_empty(): return []
		var key: String = "%d/%d/%s" % [instance.owner_id, instance.skill_instance_id, instance.definition.ability_id]
		if identities.has(key) and identities[key] != instance:
			last_error = "能力实例身份重复"
			return []
		identities[key] = instance
	for event: AbilityEvent in events:
		if event == null or event.source == null:
			last_error = "事件来源快照缺失"
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
			if instance.pending_event_id != 0 or not AbilityTriggerAdapter.matches(instance, event): continue
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
			instance.pending_event_id = event.event_id
			result.append(activation)
	return result

## 拒绝不消费；合法空结果按定义政策消费。重复或旧局完成票据无效。
func complete(activation: AbilityActivation, applied: bool, affected_count: int) -> bool:
	if activation == null or activation.event == null or activation.instance == null or affected_count < 0:
		last_error = "无效能力应用结果"
		return false
	if not _active or activation.completed or activation.event.scope != _scope: return false
	var instance: AbilityInstance = activation.instance
	if instance.pending_event_id != activation.event.event_id: return false
	instance.pending_event_id = 0
	activation.completed = true
	if applied and (affected_count > 0 or instance.definition.consume_on_empty):
		instance.trigger_count += 1
	return applied

## 关闭本局分发器；旧事件与未完成票据随后失效。
func close() -> void:
	_active = false
	_dispatched.clear()

## 导出去重与编号状态，供规则快照记录。
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
