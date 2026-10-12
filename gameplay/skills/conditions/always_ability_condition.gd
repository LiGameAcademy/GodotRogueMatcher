class_name AlwaysAbilityCondition
extends TriggerCondition

## 始终成立的只读条件，用作组合条件中的恒真叶。
func evaluate(_context: Dictionary) -> bool:
	return true
