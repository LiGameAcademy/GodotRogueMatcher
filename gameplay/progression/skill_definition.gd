class_name SkillDefinition
extends Resource

enum Action { CORE_DROP, ASSIGN_FUSE, BLAST_RADIUS, BLAST_REWARD, SCORE_MULTIPLIER, MATCH_EXTRA, BLAST_EXTRA, THIN }

@export var skill_id: StringName
@export var title: String
@export_multiline var description: String
## 卡面摘要；完整规则仍由description保存，不参与玩法配置哈希。
@export_multiline var short_description: String
@export var action: Action
@export var base_weight: float = 1.0
@export var tags: Array[StringName] = []
@export var is_starter: bool = false
@export var is_persistent: bool = true
@export var fallback_only: bool = false
@export var need_rule: StringName
@export var rescue_offer: bool = false
@export var minimum_reward: int = 1
@export var target_count: int = 3
@export var choice_effect: ChoiceEffect
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
@export var rarity: Rarity = Rarity.COMMON
@export var requires_core: bool = false
@export var requires_fuse_unlock: bool = false
@export var requires_fuse: bool = false
@export var prerequisite: StringName
@export var maximum_level: int = 0
@export var levels: Array[SkillLevelDefinition] = []

## 返回下一次取得/升级效果；未迁移的卡仍沿用原选择效果。
func acquisition_effect(current_level: int = 0) -> ChoiceEffect:
	if levels.is_empty(): return choice_effect
	if current_level < 0 or current_level >= levels.size(): return null
	var config: SkillLevelDefinition = levels[current_level]
	if config == null or config.abilities.size() != 1 or config.abilities[0] == null: return null
	return config.abilities[0].effect as ChoiceEffect

func validation_error() -> String:
	if levels.is_empty(): return ""
	if skill_id.is_empty() or not is_persistent: return "等级技能需稳定ID与持久生命周期"
	if choice_effect != null: return "等级技能不能同时配置旧选择效果"
	if maximum_level != levels.size(): return "等级配置与等级上限不符"
	var ability_id: StringName = &""
	for index: int in range(levels.size()):
		var config: SkillLevelDefinition = levels[index]
		if config == null or config.level != index + 1: return "等级配置不连续"
		var error: String = config.validation_error()
		if not error.is_empty(): return error
		if not ability_id.is_empty() and ability_id != config.abilities[0].ability_id:
			return "升级必须保留能力ID以延续运行状态"
		ability_id = config.abilities[0].ability_id
	return ""
