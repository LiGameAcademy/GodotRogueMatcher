class_name ItemRegistry
extends RefCounted

## 旧道具配置的局部工厂；不注册、不订阅正式对局。

## 创建棱镜塔 (Prism Tower)
## 效果：参与消除时，该次得分 x2
## 仅保留旧配置；不进入正式取得与自动触发路径。
func create_prism_tower() -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = "prism_tower"
	item.rarity = "COMMON"
	item.type = "BUILDING"
	item.occupies_space = true
	item.can_be_eliminated = true
	item.base_color = 4  # 紫色 - 星形
	item.icon = preload("res://assets/icons/prism_tower.svg")
	item.effect_config = null  # 历史占位配置
	return item

## 创建增幅器 (Amplifier)
## 效果：周围8格发生的消除 +100%
## 仅保留旧配置；不进入正式取得与自动触发路径。
func create_amplifier() -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = "amplifier"
	item.rarity = "COMMON"
	item.type = "BUILDING"
	item.occupies_space = true
	item.can_be_eliminated = true
	item.base_color = 0  # 红色 - 圆形
	item.icon = preload("res://assets/icons/amplifier.svg")
	item.effect_config = null  # 历史占位配置
	return item

## 创建染色工厂 (Dye Station)
## 效果：回合开始时将上下左右4格中1个随机球染成指定颜色
## 仅保留旧配置；不进入正式取得与自动触发路径。
func create_dye_station() -> ItemData:
	var effect: EffectDyePiece = EffectDyePiece.new()
	effect.effect_id = "dye_piece"
	effect.target_color = -1  # 可在放置时指定，这里默认随机
	effect.dye_range = "adjacent"  # 上下左右4格
	effect.dye_count = 1

	var config: ItemEffectConfig = ItemEffectConfig.new()
	var effects_arr: Array[GameplayEffect] = []
	effects_arr.append(effect)
	config.effects = effects_arr
	var conditions_arr: Array[GameplayCondition] = []
	config.conditions = conditions_arr

	var item: ItemData = ItemData.new()
	item.id = "dye_station"
	item.rarity = "COMMON"
	item.type = "BUILDING"
	item.occupies_space = true
	item.can_be_eliminated = true
	item.base_color = 3  # 黄色 - 五边形
	item.icon = preload("res://assets/icons/dye_station.svg")
	item.effect_config = config
	return item

## 创建以太图腾 (Ether Totem)
## 效果：涉及红球的消除得分 x1.5
## 仅保留旧配置；不进入正式取得与自动触发路径。
func create_ether_totem() -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = "ether_totem"
	item.rarity = "RARE"
	item.type = "RELIC"
	item.occupies_space = true
	item.can_be_eliminated = true
	item.base_color = 2  # 蓝色 - 三角形
	item.icon = preload("res://assets/icons/ether_totem.svg")
	item.effect_config = null  # 历史占位配置
	return item

## 创建能量核心 (Energy Core)
## 效果：所有消除得分 +50%
## 仅保留旧配置；不进入正式取得与自动触发路径。
func create_energy_core() -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = "energy_core"
	item.rarity = "RARE"
	item.type = "RELIC"
	item.occupies_space = true
	item.can_be_eliminated = true
	item.base_color = 1  # 绿色 - 方形
	item.icon = preload("res://assets/icons/energy_core.svg")
	item.effect_config = null  # 历史占位配置
	return item

## 创建空间压缩机 (Space Compressor)
## 效果：新生成的球有 20% 几率成为幽灵球
## 仅保留旧配置；不进入正式取得与自动触发路径。
func create_space_compressor() -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = "space_compressor"
	item.rarity = "RARE"
	item.type = "BUILDING"
	item.occupies_space = true
	item.can_be_eliminated = true
	item.base_color = 0  # 红色 - 圆形
	item.icon = preload("res://assets/icons/space_compressor.svg")
	item.effect_config = null  # 历史占位配置
	return item
