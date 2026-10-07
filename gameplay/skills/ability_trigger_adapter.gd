class_name AbilityTriggerAdapter
extends RefCounted

const MAX_CONDITION_DEPTH: int = 8

## 复用插件的只读条件判断，实例次数仍属于本局。
## 不activate/execute共享Resource，不订阅全局总线、不使用时间或全局RNG。
static func validation_error(definition: AbilityDefinition) -> String:
	if definition == null or definition.effect == null: return "能力效果缺失"
	var trigger: GameplayTrigger = definition.trigger
	if trigger == null: return "能力触发配置缺失"
	if trigger.trigger_type != GameplayTrigger.TRIGGER_TYPE.ON_EVENT or trigger.trigger_event.is_empty():
		return "本局能力仅支持明确事件触发"
	if trigger.trigger_chance != 1.0:
		return "概率触发尚未接入局内随机协议"
	if trigger.trigger_count != 0:
		return "共享触发定义含运行计数"
	for condition: TriggerCondition in trigger.conditions:
		var error: String = _condition_error(condition, [])
		if not error.is_empty(): return error
	return ""

static func try_accept(instance: AbilityInstance, event: AbilityEvent) -> bool:
	if not validation_error(instance.definition).is_empty(): return false
	if event.source == null or instance.owner_id != event.source.piece_id: return false
	var trigger: GameplayTrigger = instance.definition.trigger
	if trigger.trigger_event != event.event_type: return false
	if trigger.max_triggers > 0 and instance.trigger_count >= trigger.max_triggers: return false
	if not trigger.should_trigger(event.to_context()): return false
	instance.trigger_count += 1
	return true

static func _condition_error(condition: TriggerCondition, ancestors: Array[TriggerCondition]) -> String:
	if condition == null: return "能力触发条件缺失"
	if ancestors.has(condition): return "能力触发条件循环引用"
	if ancestors.size() >= MAX_CONDITION_DEPTH: return "能力触发条件嵌套过深"
	if condition is CompositeTriggerCondition:
		var composite: CompositeTriggerCondition = condition as CompositeTriggerCondition
		if not ["AND", "OR", "XOR", "NAND", "NOR"].has(composite.operator): return "未知条件组合运算"
		ancestors.append(condition)
		for child: TriggerCondition in composite.conditions:
			var error: String = _condition_error(child, ancestors)
			if not error.is_empty(): return error
		ancestors.pop_back()
	return ""
