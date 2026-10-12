class_name AbilityActivation
extends RefCounted

## 分发后冻结的执行票据；规则提交成功后才更新能力次数。
var event: AbilityEvent
var instance: AbilityInstance
## 是否已完成一次提交（含拒绝与合法空结果）。
var completed: bool = false
