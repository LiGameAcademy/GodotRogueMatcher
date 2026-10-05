extends Resource
class_name GameplayCondition

## 游戏条件基类
## 职责：定义触发条件的检查接口

## 条件ID（用于调试和日志）
var condition_id: String = ""

## 检查条件是否满足
## [param context: Dictionary] 上下文数据
## [return: bool] 条件是否满足
func check(_context: Dictionary = {}) -> bool:
	push_error("GameplayCondition.check() 必须在子类中实现")
	return false

## 获取条件描述
## [return: String] 条件描述
func get_description() -> String:
	return "未实现的条件"

