class_name ManualActivationRules
extends RefCounted

const CORE: SkillDefinition = preload("res://gameplay/progression/content/core_manual_detonation.tres")
const LINE: SkillDefinition = preload("res://gameplay/progression/content/line_manual_clear.tres")

static func skill(line: bool) -> SkillDefinition:
	return LINE if line else CORE

## This quota belongs to the run/card, never to an individual piece or chain event.
static func remaining_count(used: Dictionary[StringName, int], definition: SkillDefinition) -> int:
	return maxi(0, definition.manual_use_limit - used.get(definition.skill_id, 0))

static func remaining(state: RunState, line: bool) -> int:
	var level: int = state.line_clear.level(LINE.skill_id) if line else state.explosion.level(CORE.skill_id)
	return remaining_count(state.manual_uses_used, skill(line)) if level > 0 else 0

## Called once at the accepted command's commit point, after all preflight checks.
static func consume(state: RunState, line: bool) -> void:
	var id: StringName = skill(line).skill_id
	state.manual_uses_used[id] = state.manual_uses_used.get(id, 0) + 1
