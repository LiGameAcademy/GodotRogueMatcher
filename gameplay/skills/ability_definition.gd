class_name AbilityDefinition
extends Resource

## 能力唯一标识。
@export var ability_id: StringName = &""
## 明确时机；条件只查询值上下文，不持有运行计数。
@export var event_type: StringName = &""
## 附加触发条件；空数组表示无额外限制。
@export var conditions: Array[TriggerCondition] = []
## 最大触发次数；0 表示不限制。
@export var max_triggers: int = 0
## 合法空结果是否消费次数；离场爆破保留既有消费政策。
@export var consume_on_empty: bool = true
## 效果资源；加载时校验具体类型，取得与离场请求将在 #61 统一执行。
@export var effect: Resource
