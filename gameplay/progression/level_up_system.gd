extends Node

## 升级系统（单例）
## 旧道具池与进度只读兼容查询；正式奖励由本局和Game处理。

signal level_up_triggered(items: Array[ItemData])

## 当前等级
var current_level: int:
	get: return GameManager.run.state.progression.level
var pending_rewards: int:
	get:
		return GameManager.run.state.pending_rewards

## 下一个里程碑分数
var next_milestone: int:
	get: return GameManager.run.state.progression.next_milestone

const CONFIG: ProgressionConfig = preload("res://gameplay/progression/content/progression_config.tres")
var previous_milestone: int:
	get: return GameManager.run.state.progression.previous_milestone

## 物品池（待实现）
var item_pools: Dictionary = {}

func _ready() -> void:
	reset_system()

## 重置系统
func reset_system() -> void:
	initialize_item_pools()

## 初始化物品池（待实现具体物品数据）
func initialize_item_pools() -> void:
	# 初始化空的物品池
	item_pools = {
		"common": [],
		"rare": [],
		"epic": []
	}

## 注册单个道具到物品池
## [param item_data: ItemData] 道具数据资源
func register_item(item_data: ItemData) -> void:
	if not item_data:
		push_warning("尝试注册空的 ItemData")
		return
	
	# 确保稀有度有效（如果没有设置，默认为 COMMON）
	if item_data.rarity.is_empty():
		item_data.rarity = "COMMON"
	
	# 根据稀有度添加到对应池
	var rarity_key: String = item_data.rarity.to_lower()
	if not item_pools.has(rarity_key):
		# 如果稀有度不存在，添加到 common 池
		rarity_key = "common"
	
	# 检查是否已存在（避免重复注册）
	var pool: Array = item_pools[rarity_key]
	if pool.has(item_data):
		return
	
	pool.append(item_data)
	print("注册道具：", item_data.id, " (稀有度: ", item_data.rarity, ", 类型: ", item_data.type, ")")

## 批量注册道具
## [param items: Array[ItemData]] 道具数据数组
func register_items(items: Array[ItemData]) -> void:
	for item: ItemData in items:
		register_item(item)

## 从目录加载所有道具资源并注册
## [param directory_path: String] 道具资源目录路径（如 "res://data/item/"）
func load_items_from_directory(directory_path: String) -> void:
	var dir: DirAccess = DirAccess.open(directory_path)
	if not dir:
		push_error("无法打开目录: " + directory_path)
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	var loaded_count: int = 0
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var item_path: String = directory_path + file_name
			var item_data: ItemData = load(item_path) as ItemData
			if item_data:
				register_item(item_data)
				loaded_count += 1
			else:
				push_warning("无法加载道具资源: " + item_path)
		
		file_name = dir.get_next()
	
	print("从目录加载道具完成，共加载 ", loaded_count, " 个道具")

## 生成三选一选项
## [return: Array[ItemData]] 三个道具选项
func generate_options() -> Array[ItemData]:
	var options: Array[ItemData] = []
	
	# 根据等级调整稀有度概率
	var rare_chance: float = _calculate_rare_chance()
	var epic_chance: float = _calculate_epic_chance()
	
	# 生成 3 个不同内容ID的选项
	var used_ids: Array[String] = []
	
	for i: int in range(3):
		var item: ItemData = _get_random_item(rare_chance, epic_chance, used_ids)
		if item:
			options.append(item)
			used_ids.append(item.id)
	
	return options

## 计算稀有道具出现概率
## [return: float] 稀有道具概率（0.0 - 1.0）
func _calculate_rare_chance() -> float:
	return min(0.1 + current_level * 0.05, 0.5)  # 最高 50%

## 计算史诗道具出现概率
## [return: float] 史诗道具概率（0.0 - 1.0）
func _calculate_epic_chance() -> float:
	return min(0.05 + current_level * 0.02, 0.2)  # 最高 20%

## 获取随机道具
## [param rare_chance: float] 稀有道具概率
## [param epic_chance: float] 史诗道具概率
## [param used_ids: Array[String]] 已使用的内容ID（避免重复）
## [return: ItemData] 随机道具
func _get_random_item(rare_chance: float, epic_chance: float, used_ids: Array[String]) -> ItemData:
	var rand_value: float = randf()
	var pool_name: String = "common"
	if rand_value < epic_chance:
		pool_name = "epic"
	elif rand_value < rare_chance:
		pool_name = "rare"
	var candidates: Array[ItemData] = []
	var pool: Array = item_pools.get(pool_name, [])
	for item: ItemData in pool:
		if not used_ids.has(item.id):
			candidates.append(item)
	if candidates.is_empty():
		for fallback_pool: Array in item_pools.values():
			for item: ItemData in fallback_pool:
				if not used_ids.has(item.id):
					candidates.append(item)
	if candidates.is_empty():
		return null
	return candidates.pick_random()

## 获取当前等级
## [return: int] 当前等级
func get_current_level() -> int:
	return current_level

## 获取下一个里程碑
## [return: int] 下一个里程碑分数
func get_next_milestone() -> int:
	return next_milestone

## 获取升级进度（0.0 - 1.0）
## [param current_score: int] 当前分数
## [return: float] 升级进度
func get_level_progress(current_score: int) -> float:
	var progress: float = float(current_score - previous_milestone) / float(next_milestone - previous_milestone)
	return clamp(progress, 0.0, 1.0)
