class_name SkillDefinition
extends Resource

enum Action { CORE_DROP, ASSIGN_FUSE, BLAST_RADIUS, BLAST_REWARD, SCORE_MULTIPLIER, MATCH_EXTRA, BLAST_EXTRA, THIN }

@export var skill_id: StringName
@export var title: String
@export_multiline var description: String
@export var action: Action
@export var base_weight: float = 1.0
@export var tags: Array[StringName] = []
@export var is_starter: bool = false
@export var is_persistent: bool = true
@export var fallback_only: bool = false
@export var need_rule: StringName
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
