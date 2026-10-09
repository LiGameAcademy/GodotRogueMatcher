class_name SpawnState
extends RefCounted

## 每局独占；不修改共享生成配置。
var refill_batches: Dictionary[int, int] = {-1: 0, 1: 0}
var color_weights: Array[int] = []
var content_random: RandomNumberGenerator = RandomNumberGenerator.new()
var _plan: Array[SpawnToken] = []

func _init(config: SpawnConfig, run_seed: int = 0) -> void:
	color_weights = config.color_weights.duplicate()
	content_random.seed = run_seed ^ 0x535041574E

## 只在规则入口补足计划；已显示的前缀不因权重或数量变化重抽。
func ensure_plan(count: int, explosion: ExplosionState, core_color: int) -> void:
	while _plan.size() < count:
		var core: bool = false
		if explosion.core_pool_unlocked:
			var weight: int = DemolitionRules.CONFIG.core_type_weight + explosion.level(&"core_supply_up") * DemolitionRules.CONFIG.core_supply_per_level
			core = content_random.randi_range(1, DemolitionRules.CONFIG.ordinary_type_weight + weight) <= weight
		_plan.append(SpawnToken.new(draw_color(content_random), core, core_color))

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
	# 均匀权重直接抽颜色；内容随机流与落点流相互独立。
	if color_weights.all(func(weight: int) -> bool: return weight == color_weights[0]):
		return random.randi_range(0, color_weights.size() - 1)
	var total: int = 0
	for weight: int in color_weights: total += weight
	var sample: int = random.randi_range(1, total)
	for color: int in range(color_weights.size()):
		sample -= color_weights[color]
		if sample <= 0: return color
	return color_weights.size() - 1
