extends Resource
class_name ItemData

## 物品数据资源
## 用于定义游戏中的道具、建筑、遗物等物品

## 唯一标识符（用于本地化键，如 "prism_tower"）
@export var id: String = ""

## 图标
@export var icon: Texture2D = null

## 稀有度（"COMMON", "RARE", "EPIC"）
@export var rarity: String = "COMMON"

## 物品类型
@export_enum("BUILDING", "RELIC", "CONSUMABLE")
var type: String = "BUILDING"

## 是否占用空间（建筑占格，遗物不占格）
@export var occupies_space: bool = true

## 是否可消除（占格道具可参与消除，被消除后消失）
@export var can_be_eliminated: bool = true

## 基础颜色索引（0-4），用于占格道具作为棋子参与消除）
@export var base_color: int = 0

## 效果配置（道具的效果和触发条件）
## 必须在资源文件中配置，不能为空
@export var effect_config: ItemEffectConfig = null

## 放置规则（如 ["BAD_SECTOR_ONLY"]）
@export var placement_rules: Array[String] = []

## 获取本地化名称
## [return: String] 根据当前语言返回名称
func get_localized_name() -> String:
	if id.is_empty():
		return ""

	var key: String = "item." + id + ".name"
	return tr(key)

## 获取本地化描述
## [return: String] 根据当前语言返回描述
func get_localized_description() -> String:
	if id.is_empty():
		return ""

	var key: String = "item." + id + ".description"
	return tr(key)

func get_localized_type() -> String:
	if type.is_empty():
		return ""

	var key: String = "item.type." + type.to_lower()
	return tr(key)

## 获取效果描述（用于没有本地化时的回退）
## [return: String] 效果描述
func get_effect_description() -> String:
	if not effect_config:
		return ""

	var desc_parts: Array[String] = []
	for effect in effect_config.effects:
		if effect is GameplayEffect:
			desc_parts.append(effect.get_description())
	return "\n".join(desc_parts)