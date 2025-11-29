extends Resource
class_name GameplayEffect

## 游戏效果基类
## 职责：定义效果的行为接口

## 效果ID（用于调试和日志）
var effect_id: String = ""

## 应用效果
## [param context: Dictionary] 上下文数据
## [return: bool] 是否成功应用
func apply(_context: Dictionary = {}) -> bool:
	push_error("GameplayEffect.apply() 必须在子类中实现")
	return false

## 获取效果描述
## [return: String] 效果描述
func get_description() -> String:
	return "未实现的效果"

