extends Node

## 升级系统（单例）
## 职责：管理升级触发、三选一选项生成

signal level_up_triggered(items: Array[ItemData])

## 当前等级
var current_level: int = 0

## 下一个里程碑分数
var next_milestone: int = 500

## 里程碑递增倍数
@export var milestone_multiplier: float = 1.5

## 初始里程碑分数
@export var initial_milestone: int = 100

## 物品池（待实现）
var item_pools: Dictionary = {}

func _ready() -> void:
	reset_system()

## 重置系统
func reset_system() -> void:
	current_level = 0
	next_milestone = initial_milestone
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
	var rarity_key = item_data.rarity.to_lower()
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
	for item in items:
		register_item(item)

## 从目录加载所有道具资源并注册
## [param directory_path: String] 道具资源目录路径（如 "res://data/item/"）
func load_items_from_directory(directory_path: String) -> void:
	var dir = DirAccess.open(directory_path)
	if not dir:
		push_error("无法打开目录: " + directory_path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var loaded_count: int = 0
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var item_path = directory_path + file_name
			var item_data = load(item_path) as ItemData
			if item_data:
				register_item(item_data)
				loaded_count += 1
			else:
				push_warning("无法加载道具资源: " + item_path)
		
		file_name = dir.get_next()
	
	print("从目录加载道具完成，共加载 ", loaded_count, " 个道具")

## 检查是否触发升级
## [param score: int] 当前分数
## [return: bool] 是否触发升级
func check_level_up(score: int) -> bool:
	if score >= next_milestone:
		trigger_level_up()
		return true
	return false

## 触发升级
func trigger_level_up() -> void:
	current_level += 1
	
	# 计算下一个里程碑
	next_milestone = int(next_milestone * milestone_multiplier)
	
	# 生成三选一选项
	var options: Array = generate_options()
	
	# 发出升级信号
	level_up_triggered.emit(options)
	
	# 打开升级弹窗
	_open_level_up_popup(options)
	
	print("等级提升！当前等级：", current_level, "，下一个里程碑：", next_milestone)

## 打开升级弹窗
## [param items: Array] 道具选项数组
func _open_level_up_popup(items: Array) -> void:
	var popup = await UIManager.open_popup("popup_level_up", {"items": items})
	# 连接道具选择信号
	if popup.has_signal("item_selected"):
		popup.item_selected.connect(_on_item_selected)

## 道具选择回调
## [param item_data: ItemData] 选中的道具数据
func _on_item_selected(item_data: ItemData) -> void:
	# 使用 ItemPlacer 将道具放置到棋盘上
	# 获取 Board 实例（需要从场景树中查找）
	var board = get_tree().get_first_node_in_group("board")
	if board:
		ItemPlacer.place_item_randomly(board, item_data)
	else:
		print("错误：未找到 Board 节点")

## 生成三选一选项
## [return: Array[ItemData]] 三个道具选项
func generate_options() -> Array[ItemData]:
	var options: Array[ItemData] = []
	
	# 根据等级调整稀有度概率
	var rare_chance: float = _calculate_rare_chance()
	var epic_chance: float = _calculate_epic_chance()
	
	# 生成 3 个选项，确保类型不同
	var used_types: Array[String] = []
	
	for i in range(3):
		var item: ItemData = _get_random_item(rare_chance, epic_chance, used_types)
		if item:
			options.append(item)
			used_types.append(item.type)
	
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
## [param used_types: Array[String]] 已使用的类型（避免重复）
## [return: ItemData] 随机道具
func _get_random_item(rare_chance: float, epic_chance: float, used_types: Array[String]) -> ItemData:
	var rand_value: float = randf()
	var pool_name: String = "common"
	
	# 根据概率选择物品池
	if rand_value < epic_chance:
		pool_name = "epic"
	elif rand_value < rare_chance:
		pool_name = "rare"
	
	# 从对应物品池中获取道具
	var pool: Array = item_pools.get(pool_name, [])
	if pool.is_empty():
		# 如果池为空，降级到普通池
		pool = item_pools.get("common", [])
	
	if pool.is_empty():
		# 如果所有池都为空，返回 null（后续需要实现物品数据）
		return null
	
	# 随机选择一个道具
	var item: ItemData = pool[randi() % pool.size()]
	
	# 如果类型已使用，尝试重新选择（最多尝试 5 次）
	var attempts: int = 0
	while used_types.has(item.type) and attempts < 5:
		item = pool[randi() % pool.size()]
		attempts += 1
	
	return item

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
	if current_level == 0:
		return float(current_score) / float(initial_milestone)
	
	var previous_milestone: int = int(initial_milestone * pow(milestone_multiplier, current_level - 1))
	var progress: float = float(current_score - previous_milestone) / float(next_milestone - previous_milestone)
	return clamp(progress, 0.0, 1.0)
