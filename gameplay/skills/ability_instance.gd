class_name AbilityInstance
extends RefCounted

## 本局能力运行实例。共享只读定义，次数与待执行事件按实例独占。
var owner_id: int = 0
var skill_instance_id: int = 0
var definition: AbilityDefinition
var trigger_count: int = 0
var pending_event_id: int = 0
var has_triggered: bool:
	get:
		return trigger_count > 0
