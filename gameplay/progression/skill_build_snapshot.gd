class_name SkillBuildSnapshot
extends RefCounted

## Read-only projection of authority and successful history; never installs or samples.
var invested: Array[StringName] = []
var supplied: Array[StringName] = []
var rewarded: Array[StringName] = []
var capabilities: Array[StringName] = []

static func capture(state: RunState, definitions: Array[SkillDefinition]) -> SkillBuildSnapshot:
	var result: SkillBuildSnapshot = SkillBuildSnapshot.new()
	if state.explosion.core_pool_unlocked:
		result.capabilities.append(&"core_supply")
		result.supplied.append(&"blast")
	if state.explosion.fuse_unlocked: result.capabilities.append(&"fuse_unlocked")
	if state.line_clear.row_unlocked: result.capabilities.append(&"row_supply")
	if state.line_clear.column_unlocked: result.capabilities.append(&"column_supply")
	if state.line_clear.row_unlocked or state.line_clear.column_unlocked:
		result.capabilities.append(&"line_supply")
		result.supplied.append(&"line")
	if state.dye.level(&"match_dye_echo") > 0:
		result.capabilities.append(&"dye_engine")
		result.supplied.append(&"dye")
	if state.explosion.level(&"core_fuse_payload") > 0 or state.explosion.level(&"fuse_match_plant") > 0:
		result.supplied.append(&"fuse")
	if state.explosion.blast_extra_level > 0 or state.explosion.reward_level > 0: result.rewarded.append(&"blast")
	if state.line_clear.level(&"line_clear_score") > 0: result.rewarded.append(&"line")
	if state.dye.level(&"dye_mark_reward") > 0: result.rewarded.append(&"dye")
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id.is_empty() and state.explosion.instances.has(piece.piece_id):
			result.capabilities.append(&"live_fuse")
			break
	for route: StringName in result.supplied: _include(result.invested, route)
	for route: StringName in result.rewarded: _include(result.invested, route)
	if state.explosion.fuse_unlocked: _include(result.invested, &"fuse")
	if not state.rules.shape_unlocks.ids().is_empty(): _include(result.invested, &"shape")
	for skill: SkillDefinition in definitions:
		if skill == null or skill.offer_traits == null: continue
		if state.rewards.acquired.get(skill.skill_id, 0) <= 0 and SkillRules.level(state, skill) <= 0: continue
		for route: StringName in skill.offer_traits.invests: _include(result.invested, route)
	return result

func related(traits: SkillOfferTraits) -> bool:
	for route: StringName in traits.affinity:
		if invested.has(route): return true
	return false

func gap_routes(traits: SkillOfferTraits) -> Array[StringName]:
	var result: Array[StringName] = []
	for route: StringName in traits.supplies:
		if invested.has(route) and not supplied.has(route): _include(result, route)
	for route: StringName in traits.payoffs:
		if invested.has(route) and not rewarded.has(route): _include(result, route)
	return result

func data() -> Dictionary:
	return {"invested": invested.duplicate(), "supplied": supplied.duplicate(), "rewarded": rewarded.duplicate(), "capabilities": capabilities.duplicate()}

static func _include(values: Array[StringName], value: StringName) -> void:
	if not values.has(value): values.append(value)
