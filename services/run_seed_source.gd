class_name RunSeedSource
extends RefCounted

## 应用入口独占的熵源；不消费局内随机流。相邻新局不能复用种子。
var _random: RandomNumberGenerator
var _previous: int = -1

func _init(random_source: RandomNumberGenerator = null) -> void:
	_random = random_source if random_source != null else RandomNumberGenerator.new()
	if random_source == null:
		_random.randomize()

func next_seed() -> int:
	var sample: int = _random.randi()
	if sample == _previous:
		# 有界处理碰撞，不为抽到不同值而反复消费随机数。
		sample = (sample + 1) & 0xFFFFFFFF
	_previous = sample
	return sample
