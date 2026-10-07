class_name RemovalCauseCondition
extends TriggerCondition

## 项目自己的消除原因规则，通过插件的条件契约组合。
@export var allowed_causes: Array[StringName] = []

func evaluate(context: Dictionary) -> bool:
	var cause: Variant = context.get("cause")
	if not (cause is String or cause is StringName): return false
	if StringName(cause) == &"consume" and context.get("content_id") != &"special_demolition": return false
	return allowed_causes.has(StringName(cause))
