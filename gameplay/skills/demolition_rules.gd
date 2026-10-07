class_name DemolitionRules
extends RefCounted

const CONFIG: DemolitionConfig = preload("res://gameplay/skills/content/demolition_config.tres")

static func root_id(state: RunState) -> int:
	return state.action_id if state.rule_action_id < 0 else state.rule_action_id

static func action(state: RunState) -> DemolitionActionState:
	var id: int = root_id(state)
	if not state.explosion.actions.has(id): state.explosion.actions[id] = DemolitionActionState.new()
	return state.explosion.actions[id]

static func radius(state: RunState, source: PieceState, generation: int, base: int) -> int:
	var extra: int = state.explosion.radius_level
	if source.content_id == &"special_demolition": extra += state.explosion.level(&"core_radius")
	elif generation >= 2: extra += state.explosion.level(&"blast_chain_radius")
	return mini(CONFIG.maximum_radius, base + extra)

static func marked_score(state: RunState, pieces: Array[PieceState]) -> int:
	var count: int = 0
	var counted: Array[int] = []
	for piece: PieceState in pieces:
		if piece.piece_id in counted or state.rules.state.get_piece(piece.piece_id) == null: continue
		if piece.content_id.is_empty() and state.explosion.instances.has(piece.piece_id):
			counted.append(piece.piece_id)
			count += 1
	return count * state.explosion.level(&"marked_reward") * CONFIG.marked_reward

static func match_score(state: RunState, count: int) -> int:
	if count == 5: return state.explosion.level(&"precision_reward") * CONFIG.precision_reward
	if count >= 6: return state.explosion.level(&"longline_reward") * CONFIG.longline_reward
	return 0

## 距离、坐标、ID稳定排序；每次重新查询存活目标，不复用失效快照。
static func mark_near(resolver: AbilityResolver, centers: Array[Vector2i], distance: int, count: int, orthogonal: bool = false) -> Array[int]:
	var candidates: Array[PieceState] = []
	for piece: PieceState in resolver.state.rules.state.get_snapshot():
		if not piece.content_id.is_empty() or resolver.state.explosion.instances.has(piece.piece_id): continue
		var nearest: int = _distance(piece.coordinate, centers, orthogonal)
		if nearest <= distance: candidates.append(piece)
	candidates.sort_custom(func(a: PieceState, b: PieceState) -> bool:
		var da: int = _distance(a.coordinate, centers, orthogonal)
		var db: int = _distance(b.coordinate, centers, orthogonal)
		if da != db: return da < db
		if a.coordinate.y != b.coordinate.y: return a.coordinate.y < b.coordinate.y
		if a.coordinate.x != b.coordinate.x: return a.coordinate.x < b.coordinate.x
		return a.piece_id < b.piece_id)
	var marked: Array[int] = []
	for piece: PieceState in candidates:
		if marked.size() >= count: break
		if resolver.assign_fuse(piece.piece_id): marked.append(piece.piece_id)
	return marked

static func relay(resolver: AbilityResolver) -> Array[int]:
	var marked: Array[int] = []
	if resolver.state.explosion.level(&"fuse_relay") == 0: return marked
	var sources: Array[PieceState] = []
	for piece: PieceState in resolver.state.rules.state.get_snapshot():
		if piece.content_id.is_empty() and resolver.state.explosion.instances.has(piece.piece_id): sources.append(piece.copy())
	sources.sort_custom(func(a: PieceState, b: PieceState) -> bool: return a.piece_id < b.piece_id)
	var maximum: int = CONFIG.relay_count + resolver.state.explosion.level(&"relay_capacity")
	for source: PieceState in sources:
		if marked.size() >= maximum: break
		marked.append_array(mark_near(resolver, [source.coordinate], 1, 1, true))
	return marked

static func settle(state: RunState, id: int) -> Array[MatchResult]:
	var results: Array[MatchResult] = []
	var stats: DemolitionActionState = state.explosion.actions.get(id)
	if stats == null: return results
	if stats.effective_blasts >= 2 and state.explosion.level(&"chain_reward") > 0:
		var result: MatchResult = MatchResult.new()
		result.cause = &"bonus"
		result.score_entry = state.ledger.commit(0, 1.0, CONFIG.chain_reward * state.explosion.level(&"chain_reward"), &"chain_reward", id, [])
		results.append(result)
	if stats.blast_removed >= CONFIG.relief_threshold and state.explosion.level(&"blast_refill_relief") > 0:
		state.spawning.extend_refill(-1, 1)
	state.explosion.actions.erase(id)
	return results

static func _distance(coordinate: Vector2i, centers: Array[Vector2i], orthogonal: bool) -> int:
	var nearest: int = 2147483647
	for center: Vector2i in centers:
		var delta: Vector2i = (coordinate - center).abs()
		nearest = mini(nearest, delta.x + delta.y if orthogonal else maxi(delta.x, delta.y))
	return nearest
