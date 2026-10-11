class_name SkillLevelDefinition
extends Resource

## 每级只读配置。首个迁移切片支持一个取得能力；多效果执行在#61扩展。
@export var level: int = 1
@export var abilities: Array[AbilityDefinition] = []

func validation_error() -> String:
	if level < 1 or abilities.size() != 1: return "本片等级配置需要一个取得能力"
	var ability: AbilityDefinition = abilities[0]
	if ability == null or ability.ability_id.is_empty(): return "能力ID缺失"
	if ability.trigger != null: return "取得能力不能同时配置旧触发器"
	var expected: StringName = &"skill_acquired" if level == 1 else &"skill_upgraded"
	if ability.event_type != expected: return "取得/升级时机与等级不符"
	if not ability.effect is ChoiceEffect: return "取得能力需要选择效果"
	return ""
