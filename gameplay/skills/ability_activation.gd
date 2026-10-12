class_name AbilityActivation
extends RefCounted

## Frozen execution ticket after dispatch; ability counts update only after rule commit.
var event: AbilityEvent
var instance: AbilityInstance
## Whether one completion was recorded (including rejected and legal empty results).
var completed: bool = false
## AbilityTriggerAdapter.explain() snapshot taken at dispatch for RuleResult.activations.
var debug: Dictionary = {}
