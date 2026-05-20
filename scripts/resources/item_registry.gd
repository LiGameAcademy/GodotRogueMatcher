extends Node

## 道具注册表
## 职责：在游戏开始时创建并注册所有道具数据
## 注意：实际效果在 MatchSystem 和 SpawnManager 中实现

func _ready() -> void:
	register_all_items()

## 注册所有道具
func register_all_items() -> void:
	var level_up_system = get_node_or_null("/root/LevelUpSystem")
	if not level_up_system:
		push_error("ItemRegistry: LevelUpSystem 未找到!")
		return

	# 注册普通道具
	level_up_system.register_item(create_prism_tower())
	level_up_system.register_item(create_amplifier())
	level_up_system.register_item(create_dye_station())

	# 注册稀有道具
	level_up_system.register_item(create_ether_totem())
	level_up_system.register_item(create_energy_core())
	level_up_system.register_item(create_space_compressor())

	print("ItemRegistry: 已注册 6 个道具")

## 创建棱镜塔 (Prism Tower)
## 效果：参与消除时，该次得分 x2
## 实现：MatchSystem 在计算分数时检测
func create_prism_tower() -> ItemData:
	var item = ItemData.new()
	item.id = "prism_tower"
	item.rarity = "COMMON"
	item.type = "BUILDING"
	item.occupies_space = true
	item.effect_config = null  # 效果在 MatchSystem 中实现
	return item

## 创建增幅器 (Amplifier)
## 效果：周围8格发生的消除 +100%
## 实现：MatchSystem 在计算分数时检测
func create_amplifier() -> ItemData:
	var item = ItemData.new()
	item.id = "amplifier"
	item.rarity = "COMMON"
	item.type = "BUILDING"
	item.occupies_space = true
	item.effect_config = null  # 效果在 MatchSystem 中实现
	return item

## 创建染色工厂 (Dye Station)
## 效果：回合开始时将上下左右4格中1个随机球染成指定颜色
## 实现：ItemEffectSystem 在回合开始时触发
func create_dye_station() -> ItemData:
	var effect = EffectDyePiece.new()
	effect.effect_id = "dye_piece"
	effect.target_color = -1  # 可在放置时指定，这里默认随机
	effect.dye_range = "adjacent"  # 上下左右4格
	effect.dye_count = 1

	var config = ItemEffectConfig.new()
	var effects_arr: Array[GameplayEffect] = []
	effects_arr.append(effect)
	config.effects = effects_arr
	var conditions_arr: Array[GameplayCondition] = []
	config.conditions = conditions_arr

	var item = ItemData.new()
	item.id = "dye_station"
	item.rarity = "COMMON"
	item.type = "BUILDING"
	item.occupies_space = true
	item.effect_config = config
	return item

## 创建以太图腾 (Ether Totem)
## 效果：涉及红球的消除得分 x1.5
## 实现：MatchSystem 在计算分数时检测
func create_ether_totem() -> ItemData:
	var item = ItemData.new()
	item.id = "ether_totem"
	item.rarity = "RARE"
	item.type = "RELIC"
	item.occupies_space = true
	item.effect_config = null  # 效果在 MatchSystem 中实现
	return item

## 创建能量核心 (Energy Core)
## 效果：所有消除得分 +50%
## 实现：MatchSystem 在计算分数时作为全局加成
func create_energy_core() -> ItemData:
	var item = ItemData.new()
	item.id = "energy_core"
	item.rarity = "RARE"
	item.type = "RELIC"
	item.occupies_space = true
	item.effect_config = null  # 效果在 MatchSystem 中实现
	return item

## 创建空间压缩机 (Space Compressor)
## 效果：新生成的球有 20% 几率成为幽灵球
## 实现：SpawnManager 在生成球时检测
func create_space_compressor() -> ItemData:
	var item = ItemData.new()
	item.id = "space_compressor"
	item.rarity = "RARE"
	item.type = "BUILDING"
	item.occupies_space = true
	item.effect_config = null  # 效果在 SpawnManager 中实现
	return item