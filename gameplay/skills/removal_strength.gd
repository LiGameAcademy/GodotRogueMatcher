class_name RemovalStrength
extends RefCounted

## Per-trigger scalar snapshot. Targets and their marks are deliberately queried at execution.
var line_sweep: bool = false
var ability_id: StringName
var radius: int = 0
var cross_radius: int = -1
var per_target: int = 0
var fixed_bonus: int = 0
var marked_bonus: int = 0
var dye_bonus: int = 0
var multiplier_bonus: float = 0.0
var selective: bool = false
var payload_radius: int = 0
var payload_count: int = 0

static func capture(state: RunState, config: ExplosionConfig, source: PieceState, generation: int, ability: AbilityDefinition, synthetic: bool = false) -> RemovalStrength:
	var value: RemovalStrength = RemovalStrength.new()
	value.line_sweep = ability.effect is LineSweepEffect
	value.ability_id = &"blast_aftershock" if synthetic else ability.ability_id
	value.marked_bonus = state.explosion.level(&"marked_reward") * DemolitionRules.CONFIG.marked_reward
	if value.line_sweep:
		var axis: int = LineClearState.axis_of(source.content_id)
		value.radius = LineClearRules.radius(state.line_clear, axis)
		value.cross_radius = LineClearRules.cross_radius(state.line_clear, axis)
		value.per_target = LineClearRules.score_per_target(state.line_clear.level(&"line_clear_score"))
		value.fixed_bonus = state.explosion.match_extra_level * config.bonus_per_match
		value.dye_bonus = state.dye.level(&"dye_mark_reward") * DyeRules.CONFIG.mark_reward
		value.multiplier_bonus = state.explosion.multiplier_level * config.multiplier_per_level
	else:
		value.radius = DemolitionRules.CONFIG.aftershock_radius if synthetic else DemolitionRules.radius(state, source, generation, config.base_radius)
		value.per_target = state.explosion.reward_level * config.reward_per_target
		value.fixed_bonus = state.explosion.blast_extra_level * config.bonus_per_blast
		if generation >= 2:
			value.fixed_bonus += DemolitionRules.CONFIG.chain_bonus * state.explosion.level(&"blast_chain_bonus") * mini(generation - 1, DemolitionRules.CONFIG.chain_depth_cap)
		value.selective = state.explosion.level(&"selective_blast") > 0
		if not synthetic and source.content_id == &"special_demolition" and state.explosion.level(&"core_fuse_payload") > 0:
			value.payload_radius = DemolitionRules.CONFIG.payload_radius
			value.payload_count = DemolitionRules.CONFIG.payload_count
	return value

func extra_score(state: RunState, pieces: Array[PieceState]) -> int:
	if pieces.is_empty(): return 0
	var total: int = fixed_bonus + pieces.size() * per_target
	for piece: PieceState in pieces:
		if piece.content_id.is_empty() and state.explosion.instances.has(piece.piece_id): total += marked_bonus
		if line_sweep and state.dye.marks.has(piece.piece_id): total += dye_bonus
	return total

func data() -> Dictionary:
	return {"ability_id": ability_id, "line_sweep": line_sweep, "radius": radius, "cross_radius": cross_radius,
		"per_target": per_target, "fixed_bonus": fixed_bonus, "marked_bonus": marked_bonus,
		"dye_bonus": dye_bonus, "multiplier_bonus": multiplier_bonus, "selective": selective,
		"payload_radius": payload_radius, "payload_count": payload_count}
