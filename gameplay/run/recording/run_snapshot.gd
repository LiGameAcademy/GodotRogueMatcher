class_name RunSnapshot
extends RefCounted

const RULES_VERSION: String = "run-commands-v1"

## 所有整数转十进制字符串；坐标、实体、字典有固定规范顺序。
static func normalize(value: Variant) -> Variant:
	if value is int: return str(value)
	if value is StringName: return String(value)
	if value is Vector2i: return [str(value.x), str(value.y)]
	if value is Array:
		var result: Array = []
		for element: Variant in value: result.append(normalize(element))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[String(key)] = normalize(value[key])
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
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG: skills.append(resource_fields(skill))
	return normalize({"rules": RULES_VERSION, "columns": run.state.rules.state.columns, "rows": run.state.rules.state.rows, "match_count": run.state.rules.minimum_match_count, "colors": 5, "spawn_count": 3, "score_formula": "n*(n+5),floor(B*G+E)", "explosion": resource_fields(run.abilities.config), "progression": resource_fields(RunController.PROGRESSION), "offer": resource_fields(SkillOfferGenerator.CONFIG), "skills": skills})

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
		targets[String(skill.skill_id)] = {"coordinate": target.coordinate, "ids": target.piece_ids}
	return normalize({"offer_id": offer.offer_id, "reward_id": offer.reward_id, "choices": choices, "targets": targets, "weights": offer.weights, "generation_order": offer.generation_order, "candidate_before": offer.candidate_state_before, "candidate_after": offer.candidate_state_after, "log": offer.pool_log})

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
	ids.assign(state.explosion.instances.keys())
	ids.sort()
	for id: int in ids:
		var ability: AbilityInstance = state.explosion.instances[id]
		instances.append({"id": str(id), "ability": String(ability.definition.ability_id), "triggered": ability.has_triggered})
	return normalize({"pieces": pieces, "instances": instances, "levels": [state.explosion.radius_level, state.explosion.reward_level, state.explosion.multiplier_level, state.explosion.match_extra_level, state.explosion.blast_extra_level], "unlocked": state.explosion.unlocked, "ledger": entries, "total": state.ledger.total, "phase": state.phase, "continuation": run.continuation, "direct_match": run.direct_match(), "turn": state.turn_count, "action": state.action_id, "moves": state.valid_moves, "last_command": run.last_command_id, "pending": state.pending_rewards, "milestone_level": state.progression.level, "previous_milestone": state.progression.previous_milestone, "next_milestone": state.progression.next_milestone, "acquired": state.rewards.acquired, "consumed": state.rewards.consumed_count, "history": state.rewards.previous_unselected, "offer": offer_data(state.rewards.active_offer), "next_offer_id": state.rewards.next_offer_id, "next_piece_id": state.rules.state.next_piece_id(), "next_event_id": state.ledger.next_event_id(), "game_over": state.is_game_over, "error": state.rule_error, "random": [random_data(state.random), random_data(state.rewards.candidate_random), random_data(state.rewards.target_random), random_data(state.rewards.display_random)]})

static func canonical(data: Variant) -> String:
	return JSON.stringify(normalize(data), "", true)

static func digest(data: Variant) -> String:
	return canonical(data).sha256_text()
