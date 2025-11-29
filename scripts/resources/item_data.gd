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

## 是否占用空间
@export var occupies_space: bool = true

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
