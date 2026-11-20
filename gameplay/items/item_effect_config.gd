extends Resource
class_name ItemEffectConfig

## 旧配置的序列化时机值保留；调用者显式传入上下文，不订阅正式对局。
enum TriggerTiming { ON_PLACE, ON_TURN_START, ON_TURN_END, ON_MATCH, ON_MOVE }

## 道具效果配置
## 职责：定义道具的效果和触发条件组合

## 效果列表
@export var effects: Array[GameplayEffect] = []

## 条件列表（所有条件必须满足）
@export var conditions: Array[GameplayCondition] = []

## 检查条件是否满足
## [param context: Dictionary] 上下文数据
## [return: bool] 所有条件是否满足
func check_conditions(context: Dictionary = {}) -> bool:
	if conditions.is_empty():
		return true  # 无条件，总是满足
	
	for condition: GameplayCondition in conditions:
		if not condition.check(context):
			return false
	
	return true

## 应用所有效果
## [param context: Dictionary] 上下文数据
## [return: bool] 是否有任何效果成功应用
func apply_effects(context: Dictionary = {}) -> bool:
	if not check_conditions(context):
		return false
	
	var any_success: bool = false
	for effect: GameplayEffect in effects:
		if effect.apply(context):
			any_success = true
	
	return any_success
