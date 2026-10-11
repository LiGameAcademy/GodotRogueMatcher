class_name AbilityDefinition
extends Resource

@export var ability_id: StringName = &""
@export var trigger: GameplayTrigger
## 取得能力使用本局事件键；旧离场触发在#60迁移。
@export var event_type: StringName = &""
## 加载边界校验具体类型；取得/离场请求将在#61统一执行。
@export var effect: Resource
