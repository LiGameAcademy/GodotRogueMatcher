extends GameplayCondition
class_name ConditionTiming

## 时机条件

## 触发时机
@export var timing: ItemEffectSystem.TriggerTiming

func _init(t: ItemEffectSystem.TriggerTiming) -> void:
	condition_id = "timing"
	timing = t

func check(context: Dictionary = {}) -> bool:
	var current_timing: ItemEffectSystem.TriggerTiming = context.get("timing", -1)
	return current_timing == timing

func get_description() -> String:
	match timing:
		ItemEffectSystem.TriggerTiming.ON_PLACE:
			return "放置时"
		ItemEffectSystem.TriggerTiming.ON_TURN_START:
			return "回合开始时"
		ItemEffectSystem.TriggerTiming.ON_TURN_END:
			return "回合结束时"
		ItemEffectSystem.TriggerTiming.ON_MATCH:
			return "消除时"
		ItemEffectSystem.TriggerTiming.ON_MOVE:
			return "移动时"
		_:
			return "未知时机"

