class_name AbilityDefinition
extends Resource

@export var ability_id: StringName = &""
## 明确时机；条件仅查询值上下文，不持有运行计数。
@export var event_type: StringName = &""
@export var conditions: Array[TriggerCondition] = []
@export var max_triggers: int = 0
## 合法空结果是否消费次数；离场爆破保留既有消费政策。
@export var consume_on_empty: bool = true
## 加载边界校验具体类型；取得/离场请求将在#61统一执行。
@export var effect: Resource
