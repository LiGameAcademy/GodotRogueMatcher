class_name SkillInstance
extends RefCounted

## 本局持有的技能。共享只读定义，等级与能力计数按实例独占。
var instance_id: int
var definition: SkillDefinition
var level: int = 0
var abilities: Array[AbilityInstance] = []

func _init(skill: SkillDefinition, installed_at: int) -> void:
	definition = skill
	instance_id = installed_at

## 调用方必须先校验下一等级；同ID能力升级保留已消费次数。
func commit_next_level() -> void:
	var next: SkillLevelDefinition = definition.levels[level]
	var updated: Array[AbilityInstance] = []
	for ability: AbilityDefinition in next.abilities:
		var runtime: AbilityInstance = null
		for current: AbilityInstance in abilities:
			if current.definition.ability_id == ability.ability_id: runtime = current
		if runtime == null:
			runtime = AbilityInstance.new()
			runtime.skill_instance_id = instance_id
		runtime.definition = ability
		runtime.trigger_count += 1
		updated.append(runtime)
	abilities = updated
	level = next.level

func data() -> Dictionary:
	var states: Array[Dictionary] = []
	for ability: AbilityInstance in abilities:
		states.append({
			"ability_id": ability.definition.ability_id,
			"event_type": ability.definition.event_type,
			"trigger_count": ability.trigger_count,
			"pending_event_id": ability.pending_event_id,
			"skill_instance_id": ability.skill_instance_id,
			"max_triggers": ability.definition.max_triggers,
			"consume_on_empty": ability.definition.consume_on_empty,
		})
	return {"instance_id": instance_id, "skill_id": definition.skill_id, "level": level, "abilities": states}
