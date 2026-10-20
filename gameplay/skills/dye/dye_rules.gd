class_name DyeRules
extends RefCounted

const CONFIG: DyeConfig = preload("res://gameplay/skills/dye/dye_config.tres")

static func match_score(state: RunState, ids: Array[int]) -> int:
	var count: int = 0
	for id: int in ids:
		if state.dye.marks.has(id): count += 1
	return count * state.dye.level(&"dye_mark_reward") * CONFIG.mark_reward

static func active(state: RunState) -> bool:
	return state.dye.level(&"match_dye_echo") > 0 and DemolitionRules.root_id(state) > 0 and state.phase in [RunState.Phase.MOVING, RunState.Phase.TURN_END, RunState.Phase.SPAWNING]

## 来源批次已收束后重查存活目标；根行动共享预算，不按出生次数刷新。
static func after_matches(resolver: AbilityResolver, matches: Array[MatchResult]) -> Array[MatchResult]:
	var state: RunState = resolver.state
	if not active(state): return []
	var has_match: bool = false
	for result: MatchResult in matches:
		if result.cause == &"match" and not result.removed.is_empty(): has_match = true
	if not has_match: return []
	state.dye.begin_root(DemolitionRules.root_id(state))
	if state.dye.considered_match and not state.dye.allow_chain: return []
	state.dye.considered_match = true
	for result: MatchResult in matches:
		if result.cause != &"match" or result.removed.is_empty(): continue
		var centers: Array[Vector2i] = []
		for piece: PieceState in result.removed: centers.append(piece.coordinate)
		var color: int = result.removed[0].match_color
		var ids: Array[int] = targets(state, centers, color, 1, true)
		if ids.is_empty(): continue
		ids.resize(mini(ids.size(), CONFIG.base_targets + state.dye.level(&"dye_target_up") * CONFIG.extra_targets))
		return _wave(resolver, ids, color)
	return []

static func after_blasts(resolver: AbilityResolver, results: Array[MatchResult]) -> Array[MatchResult]:
	var state: RunState = resolver.state
	if not active(state) or state.dye.level(&"blast_dye") == 0: return []
	state.dye.begin_root(DemolitionRules.root_id(state))
	if state.dye.considered_blast: return []
	for result: MatchResult in results:
		if result.cause != &"explosion" or result.removed.is_empty(): continue
		state.dye.considered_blast = true
		var ids: Array[int] = targets(state, [result.center], result.source_color, result.radius + CONFIG.blast_edge_extension, false)
		if ids.is_empty(): return []
		ids.resize(1)
		return _wave(resolver, ids, result.source_color)
	return []

static func targets(state: RunState, centers: Array[Vector2i], color: int, radius: int, orthogonal: bool) -> Array[int]:
	var candidates: Array[PieceState] = []
	for piece: PieceState in state.rules.state.get_snapshot():
		if not piece.content_id.is_empty() or piece.match_color == color or state.dye.dyed_ids.has(piece.piece_id): continue
		if _distance(piece.coordinate, centers, orthogonal) <= radius: candidates.append(piece)
	candidates.sort_custom(func(a: PieceState, b: PieceState) -> bool:
		var da: int = _distance(a.coordinate, centers, orthogonal)
		var db: int = _distance(b.coordinate, centers, orthogonal)
		if da != db: return da < db
		if a.coordinate.y != b.coordinate.y: return a.coordinate.y < b.coordinate.y
		if a.coordinate.x != b.coordinate.x: return a.coordinate.x < b.coordinate.x
		return a.piece_id < b.piece_id)
	var ids: Array[int] = []
	for piece: PieceState in candidates: ids.append(piece.piece_id)
	return ids

static func _distance(coordinate: Vector2i, centers: Array[Vector2i], orthogonal: bool) -> int:
	var nearest: int = 1000000
	for center: Vector2i in centers:
		var delta: Vector2i = (coordinate - center).abs()
		nearest = mini(nearest, delta.x + delta.y if orthogonal else maxi(delta.x, delta.y))
	return nearest

static func _wave(resolver: AbilityResolver, ids: Array[int], color: int) -> Array[MatchResult]:
	var state: RunState = resolver.state
	var maximum: int = CONFIG.base_waves + state.dye.level(&"dye_chain_depth") * CONFIG.extra_waves
	if state.dye.waves_used >= maximum: return []
	state.dye.waves_used += 1
	for id: int in ids: state.dye.dyed_ids.append(id)
	var previous: bool = state.dye.allow_chain
	state.dye.allow_chain = true
	var results: Array[MatchResult] = recolor(resolver, ids, color)
	state.dye.allow_chain = previous
	return results

## 同波全部改色后统一查线；零分条目只提供唯一事件身份，避免表现重播。
static func recolor(resolver: AbilityResolver, ids: Array[int], color: int) -> Array[MatchResult]:
	var state: RunState = resolver.state
	var change: MatchResult = MatchResult.new()
	change.cause = &"dye"
	for id: int in ids:
		var piece: PieceState = state.rules.state.get_piece(id)
		if piece == null or not piece.content_id.is_empty() or piece.match_color == color: continue
		change.previous_colors.append(piece.match_color)
		state.rules.set_piece_color(id, color)
		state.dye.marks[id] = DemolitionRules.root_id(state)
		change.recolored.append(state.rules.state.get_piece(id))
	if change.recolored.is_empty(): return []
	change.center = change.recolored[0].coordinate
	change.score_entry = state.ledger.commit(0, 1.0, 0, &"dye", DemolitionRules.root_id(state), ids)
	var results: Array[MatchResult] = [change]
	results.append_array(resolver.resolve(state.rules.find_matches()))
	return results

