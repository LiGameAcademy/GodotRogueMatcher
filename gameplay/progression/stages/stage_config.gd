class_name StageConfig
extends Resource

## 静态阶段表由 .tres 配置；运行期间按只读约定使用。
@export var targets: Array[int] = []
@export var action_limits: Array[int] = []

func validation_error() -> String:
	if targets.is_empty() or targets.size() != action_limits.size(): return "阶段目标与行动表必须非空且等长"
	for index: int in range(targets.size()):
		if targets[index] <= 0 or action_limits[index] <= 0: return "阶段目标与行动上限必须为正整数"
	return ""

static func from_record(data: Dictionary) -> StageConfig:
	if not data.get("targets") is Array or not data.get("action_limits") is Array: return null
	var config: StageConfig = StageConfig.new()
	config.targets.clear()
	config.action_limits.clear()
	for key: String in ["targets", "action_limits"]:
		for value: Variant in data[key]:
			if not CommandCodec.valid_integer(value): return null
			if key == "targets": config.targets.append(String(value).to_int())
			else: config.action_limits.append(String(value).to_int())
	return config if config.validation_error().is_empty() else null
