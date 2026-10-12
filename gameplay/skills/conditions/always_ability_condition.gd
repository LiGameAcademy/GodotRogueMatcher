class_name AlwaysAbilityCondition
extends TriggerCondition

## Always-true read-only condition used as a constant leaf in composites.
func evaluate(_context: Dictionary) -> bool:
	return true
