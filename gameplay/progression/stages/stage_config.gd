class_name StageConfig
extends Resource

## 静态阶段表由 .tres 配置；运行期间按只读约定使用。
@export var targets: Array[int] = []
@export var pressure_intervals: Array[int] = []
@export var base_refill: int = 3
@export var maximum_refill: int = 6

func validation_error() -> String:
	if targets.is_empty() or targets.size() != pressure_intervals.size(): return "阶段目标与升压间隔必须非空且等长"
	if base_refill < 1 or maximum_refill < base_refill or maximum_refill > RunController.SPAWN_CONFIG.maximum_refill:
		return "阶段补棋基础量与上限无效"
	for index: int in range(targets.size()):
		if targets[index] <= 0 or pressure_intervals[index] <= 0: return "阶段目标与升压间隔必须为正整数"
	return ""

static func from_record(data: Dictionary) -> StageConfig:
	if not data.get("targets") is Array or not data.get("pressure_intervals") is Array: return null
	for key: String in ["base_refill", "maximum_refill"]:
		if not CommandCodec.valid_integer(data.get(key)): return null
	var config: StageConfig = StageConfig.new()
	config.base_refill = String(data.base_refill).to_int()
	config.maximum_refill = String(data.maximum_refill).to_int()
	for key: String in ["targets", "pressure_intervals"]:
		for value: Variant in data[key]:
			if not CommandCodec.valid_integer(value): return null
			if key == "targets": config.targets.append(String(value).to_int())
			else: config.pressure_intervals.append(String(value).to_int())
	return config if config.validation_error().is_empty() else null
