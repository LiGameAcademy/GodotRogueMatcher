class_name StageConfig
extends Resource

## 离线目标表与来源由 .tres 配置；StageState 在建局时独占冻结副本。
@export var targets: Array[int] = []
@export var pressure_intervals: Array[int] = []
@export var base_refill: int = 3
@export var maximum_refill: int = 5
@export var curve_version: String = "fixed-8-targets-v1"
@export var reference_profile: String = "fixed-table-unmeasured"
@export var reference_dataset_hash: String = ""
@export var reference_rule_version: String = ""
@export var target_policy: String = "fixed_fallback"

func validation_error() -> String:
	if curve_version.is_empty() or reference_profile.is_empty() or target_policy not in ["fixed_fallback", "offline_reference"]:
		return "目标曲线版本、参考构筑与来源策略无效"
	if target_policy == "offline_reference" and (reference_dataset_hash.length() != 64 or not reference_dataset_hash.is_valid_hex_number(false) or reference_rule_version.is_empty()):
		return "离线参考曲线必须提供数据指纹与采样规则版本"
	if targets.is_empty() or targets.size() != pressure_intervals.size(): return "阶段目标与升压间隔必须非空且等长"
	if base_refill < 1 or maximum_refill < base_refill or maximum_refill > RunController.SPAWN_CONFIG.maximum_refill:
		return "阶段补棋基础量与上限无效"
	var accumulated: int = 0
	for index: int in range(targets.size()):
		if targets[index] <= 0 or pressure_intervals[index] <= 0: return "阶段目标与升压间隔必须为正整数"
		if targets[index] > 9223372036854775807 - accumulated: return "累计目标超出64位计分范围"
		accumulated += targets[index]
	return ""

static func from_record(data: Dictionary) -> StageConfig:
	if not data.get("targets") is Array or not data.get("pressure_intervals") is Array: return null
	for key: String in ["base_refill", "maximum_refill"]:
		if not CommandCodec.valid_integer(data.get(key)): return null
	var config: StageConfig = StageConfig.new()
	config.base_refill = String(data.base_refill).to_int()
	config.maximum_refill = String(data.maximum_refill).to_int()
	for key: String in ["curve_version", "reference_profile", "reference_dataset_hash", "reference_rule_version", "target_policy"]:
		if not data.get(key) is String: return null
		config.set(key, data[key])
	for key: String in ["targets", "pressure_intervals"]:
		for value: Variant in data[key]:
			if not CommandCodec.valid_integer(value): return null
			if key == "targets": config.targets.append(String(value).to_int())
			else: config.pressure_intervals.append(String(value).to_int())
	return config if config.validation_error().is_empty() else null
