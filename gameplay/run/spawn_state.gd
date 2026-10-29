class_name SpawnState
extends RefCounted

## 每局独占；不修改共享生成配置。
var refill_batches: Dictionary[int, int] = {-1: 0, 1: 0}
var color_weights: Array[int] = []
var content_random: RandomNumberGenerator
var _plan: Array[SpawnToken] = []

func _init(config: SpawnConfig, run_seed: int = 0, random: RandomNumberGenerator = null) -> void:
	color_weights = config.color_weights.duplicate()
	content_random = random if random != null else RunRandomStreams.create(run_seed, &"spawn_content")

## 只在规则入口补足计划；已显示的前缀不因权重或数量变化重抽。
func ensure_plan(count: int, explosion: ExplosionState, line_clear: LineClearState = null) -> void:
	while _plan.size() < count:
		_plan.append(_draw_token(explosion, line_clear if line_clear != null else LineClearState.new()))

func _draw_token(explosion: ExplosionState, line_clear: LineClearState) -> SpawnToken:
	var color: int = draw_color(content_random)
	var ordinary: int = DemolitionRules.CONFIG.ordinary_type_weight
	var core_weight: int = 0
	if explosion.core_pool_unlocked:
		core_weight = DemolitionRules.CONFIG.core_type_weight + explosion.level(&"core_supply_up") * DemolitionRules.CONFIG.core_supply_per_level
	var row_weight: int = 0
	var column_weight: int = 0
	if line_clear.row_unlocked:
		row_weight = LineClearRules.CONFIG.line_type_weight + line_clear.level(&"line_row_supply") * LineClearRules.CONFIG.line_supply_per_level
	if line_clear.column_unlocked:
		column_weight = LineClearRules.CONFIG.line_type_weight + line_clear.level(&"line_column_supply") * LineClearRules.CONFIG.line_supply_per_level
	var total: int = ordinary + core_weight + row_weight + column_weight
	var sample: int = content_random.randi_range(1, total) if core_weight + row_weight + column_weight > 0 else total
	if sample <= core_weight:
		return SpawnToken.new(color, true, color, -1)
	sample -= core_weight
	if sample <= row_weight:
		return SpawnToken.new(color, false, color, LineClearState.AXIS_ROW)
	sample -= row_weight
	if sample <= column_weight:
		return SpawnToken.new(color, false, color, LineClearState.AXIS_COLUMN)
	return SpawnToken.new(color, false, color, -1)

func consume_token() -> SpawnToken:
	return _plan.pop_front()

## 返回独立副本，显示、悬停与暂停不能消费随机数或改写计划。
func preview(count: int) -> Array[SpawnToken]:
	var result: Array[SpawnToken] = []
	for index: int in range(mini(count, _plan.size())):
		result.append(_plan[index].copy())
	return result

func plan_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for token: SpawnToken in _plan: result.append(token.data())
	return result

func next_refill_count(config: SpawnConfig, base_count: int = -1) -> int:
	var base: int = config.refill_count if base_count < 0 else base_count
	return clampi(base + (1 if refill_batches[1] > 0 else 0) - (1 if refill_batches[-1] > 0 else 0), config.minimum_refill, config.maximum_refill)

func extend_refill(delta: int, batches: int) -> void:
	refill_batches[delta] += batches

func consume_refill_count(config: SpawnConfig, base_count: int = -1) -> int:
	var count: int = next_refill_count(config, base_count)
	consume_refill_modifiers()
	return count

func consume_refill_modifiers() -> void:
	for delta: int in refill_batches:
		refill_batches[delta] = maxi(0, refill_batches[delta] - 1)

func draw_color(random: RandomNumberGenerator) -> int:
	return sample_color(color_weights, random)

static func sample_color(weights: Array[int], random: RandomNumberGenerator) -> int:
	var supported: Array[int] = []
	for color: int in range(weights.size()):
		if weights[color] > 0: supported.append(color)
	if supported.size() == 1: return supported[0]
	# 均匀权重直接抽颜色；内容随机流与落点流相互独立。
	if weights.all(func(weight: int) -> bool: return weight == weights[0]):
		return random.randi_range(0, weights.size() - 1)
	var total: int = 0
	for weight: int in weights: total += weight
	var sample: int = random.randi_range(1, total)
	for color: int in range(weights.size()):
		sample -= weights[color]
		if sample <= 0: return color
	return weights.size() - 1
