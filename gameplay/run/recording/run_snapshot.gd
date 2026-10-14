class_name RunSnapshot
extends RefCounted

const RULES_VERSION: String = "run-commands-v26-line-removal-sweep"

## Convert all integers to decimal strings; coordinates, entities, and dictionaries keep a fixed canonical order.
static func normalize(value: Variant) -> Variant:
	if value is SkillEffect or value is ChoiceEffect or value is SkillLevelDefinition or value is AbilityDefinition:
		if value is AbilityDefinition and not AbilityTriggerAdapter.validation_error(value as AbilityDefinition).is_empty():
			return {"invalid": AbilityTriggerAdapter.validation_error(value as AbilityDefinition)}
		if value is CompositeEffect:
			var composite_error: String = (value as CompositeEffect).validation_error()
			if not composite_error.is_empty(): return {"invalid": composite_error}
		var script: Script = value.get_script() as Script
		return {"script": script.resource_path, "parameters": resource_fields(value)}
	if value is TriggerCondition: return _condition_config(value as TriggerCondition)
	if value is int: return str(value)
	if value is StringName: return String(value)
	if value is Vector2i: return [str(value.x), str(value.y)]
	if value is Array:
		var result: Array = []
		for element: Variant in value: result.append(normalize(element))
		return result
	if value is PackedInt64Array:
		var result: Array[String] = []
		for element: int in value: result.append(str(element))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = normalize(value[key])
		return result
	return value

static func resource_fields(resource: Resource) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in resource.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result[String(property.name)] = normalize(resource.get(property.name))
	return result

static func config(run: RunController) -> Dictionary:
	var skills: Array[Dictionary] = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var fields: Dictionary = resource_fields(skill)
		# Display-only summary does not change rules; keep the full description field for existing config hashes.
		fields.erase("short_description")
		skills.append(fields)
	return normalize({"rules": RULES_VERSION, "columns": run.state.rules.state.columns, "rows": run.state.rules.state.rows, "match_count": run.state.rules.minimum_match_count, "colors": 5, "initial_piece_count": RunController.CONFIG.initial_piece_count, "spawning": resource_fields(RunController.SPAWN_CONFIG), "score_formula": "n*(n+5),floor(B*G+E)", "explosion": resource_fields(run.abilities.config), "demolition": resource_fields(DemolitionRules.CONFIG), "dye": resource_fields(DyeRules.CONFIG), "line_clear": resource_fields(LineClearRules.CONFIG), "line_trigger": normalize(AbilityResolver.LINE_SWEEP), "ability_trigger": trigger_config(AbilityResolver.EXPLOSION), "progression": resource_fields(RunController.PROGRESSION), "offer": resource_fields(SkillOfferGenerator.CONFIG), "rescue_offer": resource_fields(RescueOfferRules.CONFIG), "skills": skills, "mode_id": run.state.mode_id(), "challenge": {} if not run.state.stage.enabled() else resource_fields(run.state.stage.config)})

## Record explicit in-run trigger parameters; exclude plugin managers, time fields, and shared run counters.
static func trigger_config(ability: AbilityDefinition) -> Dictionary:
	var error: String = AbilityTriggerAdapter.validation_error(ability)
	if not error.is_empty(): return {"adapter": "local-events-v1", "invalid": error}
	var conditions: Array[Dictionary] = []
	for condition: TriggerCondition in ability.conditions: conditions.append(_condition_config(condition))
	return {"adapter": "local-events-v1", "ability_id": ability.ability_id,
		"event": ability.event_type, "limit": ability.max_triggers, "consume_on_empty": ability.consume_on_empty, "conditions": conditions}

static func _condition_config(condition: TriggerCondition) -> Dictionary:
	var script: Script = condition.get_script() as Script
	var fields: Dictionary = {}
	for property: Dictionary in condition.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_EDITOR:
			var value: Variant = condition.get(property.name)
			if value is Array:
				var values: Array = []
				for element: Variant in value:
					values.append(_condition_config(element) if element is TriggerCondition else element)
				value = values
			fields[property.name] = value
	return {"script": script.resource_path, "parameters": fields}

static func piece(piece_state: PieceState) -> Dictionary:
	return normalize({"id": piece_state.piece_id, "coordinate": piece_state.coordinate, "color": piece_state.match_color, "content_id": piece_state.content_id, "ghost": piece_state.is_ghost})

static func score(entry: ScoreEntry) -> Dictionary:
	return normalize({"event_id": entry.event_id, "action_id": entry.root_action_id, "source_id": entry.source_id, "ability_id": entry.ability_id, "targets": entry.target_ids, "reason": entry.reason, "N": entry.match_count, "B": entry.base_score, "G": entry.multiplier, "E": entry.extra_score, "final_score": entry.final_score})

static func offer_data(offer: SkillOffer) -> Dictionary:
	if offer == null: return {}
	var targets: Dictionary = {}
	var choices: Array[String] = []
	for skill: SkillDefinition in offer.choices:
		choices.append(String(skill.skill_id))
		var target: SkillTarget = offer.targets[skill.skill_id]
		var picker: SkillTarget = target.color_picker_source()
		targets[String(skill.skill_id)] = {"coordinate": target.coordinate, "ids": target.piece_ids, "color": target.color, "line_axis": target.line_axis, "line_index": target.line_index, "level_before": target.level_before, "level_after": target.level_after, "before": target.value_before, "after": target.value_after, "remaining_before": target.remaining_before, "remaining_after": target.remaining_after, "color_groups": picker.color_groups, "fuse_counts": picker.fuse_counts}
	return normalize({"offer_id": offer.offer_id, "reward_id": offer.reward_id, "choices": choices, "targets": targets, "pressure_snapshot": offer.pressure_snapshot, "rescue_multiplier": offer.rescue_multiplier, "offer_rules_version": offer.rules_version, "baseline_weights": offer.baseline_weights, "weights": offer.weights, "generation_order": offer.generation_order, "candidate_before": offer.candidate_state_before, "candidate_after": offer.candidate_state_after, "log": offer.pool_log})

static func random_data(random: RandomNumberGenerator) -> Dictionary:
	return {"seed": str(random.seed), "state": str(random.state)}

static func capture(run: RunController) -> Dictionary:
	var state: RunState = run.state
	var pieces: Array[Dictionary] = []
	for current: PieceState in state.rules.state.get_snapshot(): pieces.append(piece(current))
	var entries: Array[Dictionary] = []
	for entry: ScoreEntry in state.ledger.get_entries(): entries.append(score(entry))
	var instances: Array[Dictionary] = []
	var ids: Array[int] = []
	ids.assign(state.explosion.instances.keys() + state.line_clear.instances.keys())
	ids.sort()
	for id: int in ids:
		var ability: AbilityInstance = state.explosion.instances.get(id, state.line_clear.instances.get(id))
		instances.append({
			"id": str(id),
			"owner_id": str(ability.owner_id),
			"skill_instance_id": str(ability.skill_instance_id),
			"ability": String(ability.definition.ability_id),
			"event_type": String(ability.definition.event_type),
			"max_triggers": str(ability.definition.max_triggers),
			"consume_on_empty": ability.definition.consume_on_empty,
			"triggered": ability.has_triggered,
			"trigger_count": str(ability.trigger_count),
			"pending_event_id": str(ability.pending_event_id),
		})
	var snapshot: Dictionary = normalize({"pieces": pieces, "instances": instances, "levels": [state.explosion.radius_level, state.explosion.reward_level, state.explosion.multiplier_level, state.explosion.match_extra_level, state.explosion.blast_extra_level], "unlocked": state.explosion.unlocked, "ledger": entries, "total": state.ledger.total, "phase": state.phase, "continuation": run.continuation, "direct_match": run.direct_match(), "turn": state.turn_count, "action": state.action_id, "moves": state.valid_moves, "last_command": run.last_command_id, "pending": state.pending_rewards, "milestone_level": state.progression.level, "previous_milestone": state.progression.previous_milestone, "next_milestone": state.progression.next_milestone, "acquired": state.rewards.acquired, "consumed": state.rewards.consumed_count, "history": state.rewards.previous_unselected, "offer": offer_data(state.rewards.active_offer), "next_offer_id": state.rewards.next_offer_id, "next_piece_id": state.rules.state.next_piece_id(), "next_event_id": state.ledger.next_event_id(), "game_over": state.is_game_over, "error": state.rule_error, "random": [random_data(state.random), random_data(state.rewards.candidate_random), random_data(state.rewards.target_random), random_data(state.rewards.display_random)]})
	snapshot["spawning"] = normalize({"refill_batches": state.spawning.refill_batches, "color_weights": state.spawning.color_weights, "plan": state.spawning.plan_data(), "content_random": random_data(state.spawning.content_random), "plan_policy": "locked-prefix-conditional-core-v1"})
	snapshot["demolition"] = normalize({"upgrades": state.explosion.upgrades, "core_pool": state.explosion.core_pool_unlocked, "fuse_unlocked": state.explosion.fuse_unlocked, "rule_action_id": state.rule_action_id, "turn_action_id": run.turn_action_id, "activations": state.activations, "roots": _roots(state)})
	snapshot["line_clear"] = normalize({"row": state.line_clear.row_unlocked, "column": state.line_clear.column_unlocked, "upgrades": state.line_clear.upgrades})
	snapshot["dye"] = normalize({"upgrades": state.dye.upgrades, "marks": state.dye.marks, "root": state.dye.root_id, "waves": state.dye.waves_used, "match": state.dye.considered_match, "blast": state.dye.considered_blast, "chain": state.dye.allow_chain, "ids": state.dye.dyed_ids})
	snapshot["goal_bonus_score"] = str(state.goal_bonus_score)
	var skills: Array[Dictionary] = []
	var owned: Array[SkillInstance] = []
	owned.assign(state.skill_instances.values())
	owned.sort_custom(func(a: SkillInstance, b: SkillInstance) -> bool: return a.instance_id < b.instance_id)
	for instance: SkillInstance in owned: skills.append(instance.data())
	snapshot["skills"] = normalize(skills)
	snapshot["ability_events"] = normalize(state.ability_events.data())
	snapshot["challenge"] = normalize(state.stage.data())
	snapshot["action_refill_count"] = str(run.action_refill_count)
	snapshot["end_reason"] = String(state.end_reason)
	return snapshot

static func _roots(state: RunState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[int] = []
	ids.assign(state.explosion.actions.keys())
	ids.sort()
	for id: int in ids:
		var stats: DemolitionActionState = state.explosion.actions[id]
		result.append({"id": id, "plant": stats.plant_used, "aftershock": stats.aftershock_used, "effective_blasts": stats.effective_blasts, "removed": stats.blast_removed, "core": {} if stats.first_core == null else piece(stats.first_core)})
	return result

static func canonical(data: Variant) -> String:
	return JSON.stringify(normalize(data), "", true)

static func digest(data: Variant) -> String:
	return canonical(data).sha256_text()
