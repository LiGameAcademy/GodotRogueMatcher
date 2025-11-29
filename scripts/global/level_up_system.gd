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
@export var initial_milestone: int = 500

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
	# TODO: 从资源文件加载物品数据
	# 暂时使用空字典，后续实现
	item_pools = {
		"common": [],
		"rare": [],
		"epic": []
	}

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
	var popup = UIManager.open_popup("popup_level_up", {"items": items})
	# 连接道具选择信号
	if popup is PopupLevelUp:
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

