class_name AbilityTriggerAdapter
extends RefCounted

const MAX_CONDITION_DEPTH: int = 8

const EVENTS: Array[StringName] = [&"piece_eliminated", &"skill_acquired", &"skill_upgraded"]
const CAUSES: Array[StringName] = [&"match", &"explosion", &"skill_clear", &"consume"]

## 仅复用插件的只读条件；不激活共享触发器或订阅全局总线。
static func validation_error(definition: AbilityDefinition) -> String:
	if definition == null or definition.ability_id.is_empty(): return "能力ID缺失"
	if not EVENTS.has(definition.event_type): return "能力事件未接入"
	if definition.max_triggers < 0: return "能力次数不能为负"
	if definition.event_type == AbilityEvent.PIECE_ELIMINATED:
		if not definition.effect is ExplodeEffect: return "离场能力需要爆炸效果"
	elif not definition.effect is ChoiceEffect: return "取得能力需要选择效果"
	for condition: TriggerCondition in definition.conditions:
		var error: String = _condition_error(condition, [])
		if not error.is_empty(): return error
	return ""

## 纯查询，次数仅由应用完成后的事件分发器提交。
static func matches(instance: AbilityInstance, event: AbilityEvent) -> bool:
	if not validation_error(instance.definition).is_empty(): return false
	if event.source == null or instance.owner_id != event.source.piece_id: return false
	var definition: AbilityDefinition = instance.definition
	if definition.event_type != event.event_type: return false
	if definition.max_triggers > 0 and instance.trigger_count >= definition.max_triggers: return false
	for condition: TriggerCondition in definition.conditions:
		if not _evaluate(condition, event.to_context()): return false
	return true

static func _condition_error(condition: TriggerCondition, ancestors: Array[TriggerCondition]) -> String:
	if condition == null: return "能力触发条件缺失"
	if ancestors.has(condition): return "能力触发条件循环引用"
	if ancestors.size() >= MAX_CONDITION_DEPTH: return "能力触发条件嵌套过深"
	if condition is CompositeTriggerCondition:
		var composite: CompositeTriggerCondition = condition as CompositeTriggerCondition
		if not ["AND", "OR", "NOR"].has(composite.operator): return "未支持的条件组合运算"
		if composite.conditions.is_empty(): return "组合条件缺少子项"
		if composite.operator == "NOR" and composite.conditions.size() != 1: return "否定条件需要一个子项"
		ancestors.append(condition)
		for child: TriggerCondition in composite.conditions:
			var error: String = _condition_error(child, ancestors)
			if not error.is_empty(): return error
		ancestors.pop_back()
	elif condition is RemovalCauseCondition:
		var causes: Array[StringName] = (condition as RemovalCauseCondition).allowed_causes
		if causes.is_empty(): return "离场原因条件缺少原因"
		for cause: StringName in causes:
			if not CAUSES.has(cause): return "未支持的离场原因"
	elif condition is EventTypeTriggerCondition:
		if not EVENTS.has((condition as EventTypeTriggerCondition).event_type): return "条件事件未接入"
	elif not condition is AlwaysAbilityCondition: return "未支持的触发条件；概率尚未接入局内随机协议"
	return ""

## 固定配置顺序短路求值；拒绝未支持的插件条件，避免时间或全局随机数。
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
