class_name SkillDefinition
extends Resource

@export var skill_id: StringName
@export var title: String
@export_multiline var description: String
## 卡面摘要；完整规则仍由description保存，不参与玩法配置哈希。
@export_multiline var short_description: String
## 可空的主题短句，仅供显示，不进入规则计算/配置哈希。
@export_multiline var flavor_text: String
@export var offer_traits: SkillOfferTraits
@export var tags: Array[StringName] = []
@export var is_persistent: bool = true
@export var minimum_reward: int = 1
@export var target_count: int = 3
@export var choice_effect: ChoiceEffect
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
@export var rarity: Rarity = Rarity.COMMON
@export var prerequisite: StringName
@export var maximum_level: int = 0
## Per-card manual activations per run; zero means this card grants no manual action.
@export var manual_use_limit: int = 0
@export var levels: Array[SkillLevelDefinition] = []

## Acquire/upgrade root: direct ChoiceEffect and per-level abilities share the same runner.
func acquisition_effect(current_level: int = 0) -> SkillEffect:
	if levels.is_empty(): return choice_effect
	if current_level < 0 or current_level >= levels.size(): return null
	var config: SkillLevelDefinition = levels[current_level]
	if config == null or config.abilities.size() != 1 or config.abilities[0] == null: return null
	return config.abilities[0].effect as SkillEffect

## Color picker for clear-style leaves, including CompositeEffect roots.
func requires_color_choice(current_level: int = 0) -> bool:
	var effect: SkillEffect = acquisition_effect(current_level)
	if effect is ChoiceEffect: return (effect as ChoiceEffect).requires_color_choice()
	if effect is CompositeEffect: return (effect as CompositeEffect).requires_color_choice()
	return false

## First RefillCountEffect leaf for HUD / consume chrome (supports CompositeEffect).
func refill_effect(current_level: int = 0) -> RefillCountEffect:
	var effect: SkillEffect = acquisition_effect(current_level)
	if effect is RefillCountEffect: return effect as RefillCountEffect
	if effect is CompositeEffect:
		for child: SkillEffect in (effect as CompositeEffect).children:
			if child is RefillCountEffect: return child as RefillCountEffect
	return null

## Fuse assign stays available after another instant utility filled a reward slot.
func counts_as_utility_pick() -> bool:
	return offer_traits != null and offer_traits.utility_pick

func validation_error() -> String:
	if offer_traits == null: return "missing explicit offer traits"
	var traits_error: String = offer_traits.validation_error()
	if not traits_error.is_empty(): return traits_error
	if int(rarity) < 0 or int(rarity) > 4: return "invalid rarity"
	if minimum_reward < 1 or maximum_level < 0: return "invalid skill level or availability bounds"
	if offer_traits.upgradeable and maximum_level == 1: return "upgradeable skill needs more than one level"
	if maximum_level > 1 and not offer_traits.upgradeable: return "multiple levels require upgradeable policy"
	if levels.is_empty(): return "" if choice_effect != null else "skill has no acquisition effect"
	if skill_id.is_empty() or not is_persistent: return "leveled skills need a stable id and persistent lifetime"
	if choice_effect != null: return "leveled skills cannot also keep the legacy choice_effect"
	if maximum_level != levels.size(): return "level configs do not match maximum_level"
	var ability_id: StringName = &""
	for index: int in range(levels.size()):
		var config: SkillLevelDefinition = levels[index]
		if config == null or config.level != index + 1: return "level configs are not contiguous"
		var error: String = config.validation_error()
		if not error.is_empty(): return error
		if not ability_id.is_empty() and ability_id != config.abilities[0].ability_id:
			return "upgrades must keep the same ability id to retain run state"
		ability_id = config.abilities[0].ability_id
	return ""
