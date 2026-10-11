class_name AbilityActivation
extends RefCounted

## 分发后冻结的执行票据；执行完成后才提交能力次数。
var event: AbilityEvent
var instance: AbilityInstance
var completed: bool = false
