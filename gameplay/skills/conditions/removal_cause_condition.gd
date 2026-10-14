class_name RemovalCauseCondition
extends TriggerCondition

## 项目自己的消除原因规则，通过插件的条件契约组合。
@export var allowed_causes: Array[StringName] = []

func evaluate(context: Dictionary) -> bool:
	var cause: Variant = context.get("cause")
	if not (cause is String or cause is StringName): return false
	if StringName(cause) == &"consume":
		var content: Variant = context.get("content_id")
		if not (content is String or content is StringName): return false
		if StringName(content) != &"special_demolition" and not LineClearState.is_line_piece(StringName(content)): return false
	return allowed_causes.has(StringName(cause))
