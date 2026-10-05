class_name AbilityResolver
extends RefCounted

const DEFAULT_CONFIG: ExplosionConfig = preload("res://gameplay/skills/content/explosion_config.tres")
const EXPLOSION: AbilityDefinition = preload("res://gameplay/skills/content/on_eliminated_explosion.tres")

var state: RunState
var config: ExplosionConfig
var last_error: String = ""

func _init(run_state: RunState, rules_config: ExplosionConfig = DEFAULT_CONFIG) -> void:
	state = run_state
	config = rules_config

func add_core(coordinate: Vector2i) -> PieceState:
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"special_demolition":
			return null
	var core: PieceState = state.rules.place_piece(coordinate, config.core_color, &"special_demolition")
	if core != null:
		_attach(core.piece_id)
	return core

func assign_fuse(piece_id: int) -> bool:
	var piece: PieceState = state.rules.state.get_piece(piece_id)
	if piece == null or not piece.content_id.is_empty() or state.explosion.instances.has(piece_id):
		return false
	_attach(piece_id)
	return true

func upgrade_radius() -> bool:
	if not state.explosion.unlocked or state.explosion.radius_level >= config.maximum_radius_level:
		return false
	state.explosion.radius_level += 1
	return true

func upgrade_reward() -> bool:
	if not state.explosion.unlocked or state.explosion.reward_level >= config.reward_maximum_level:
		return false
	state.explosion.reward_level += 1
	return true

## 同代按来源ID排序；后代只在当前代完成后执行。没有UI或动画依赖。
func resolve(groups: Array[BoardMatchGroup]) -> Array[MatchResult]:
	var results: Array[MatchResult] = []
	last_error = ""
	if groups.is_empty():
		return results
	# 每个实例只能引爆一次，保守预算预检保证不会中途截断部分结算。
	if groups.size() + state.explosion.instances.size() > config.event_budget:
		last_error = "事件预算不足，拒绝结算"
		return results
	var queue: Array[BlastRequest] = []
	var global_multiplier: float = state.explosion.multiplier_level * config.multiplier_per_level
	for group: BoardMatchGroup in groups:
		var result: MatchResult = MatchResult.new()
		for piece_id: int in group.piece_ids:
			result.removed.append(state.rules.state.get_piece(piece_id))
		result.center = result.removed[result.removed.size() / 2].coordinate
		result.score_entry = state.ledger.commit(group.piece_ids.size(), LegacyScoreModifiers.calculate(state.rules.state, group) + global_multiplier, state.explosion.match_extra_level * config.bonus_per_match, &"match", state.action_id, group.piece_ids)
		results.append(result)
	for result: MatchResult in results:
		_remove_and_enqueue(result.removed, 1, queue)
	while not queue.is_empty():
		queue.sort_custom(_comes_before)
		var event: BlastRequest = queue.pop_front()
		var request: BlastRequest = event.ability.definition.effect.build_request(state.rules.state, event.source, config.base_radius + state.explosion.radius_level)
		var result: MatchResult = MatchResult.new()
		result.cause = &"explosion"
		result.source_id = event.source.piece_id
		result.center = event.source.coordinate
		result.radius = request.radius
		result.generation = event.generation
		for piece_id: int in request.target_ids:
			var target: PieceState = state.rules.state.get_piece(piece_id)
			if target != null:
				result.removed.append(target)
		var extra_score: int = 0
		if not result.removed.is_empty():
			extra_score = result.removed.size() * state.explosion.reward_level * config.reward_per_target + state.explosion.blast_extra_level * config.bonus_per_blast
		result.score_entry = state.ledger.commit(0, 1.0, extra_score, &"explosion", state.action_id, request.target_ids, result.source_id, event.ability.definition.ability_id)
		_remove_and_enqueue(result.removed, event.generation + 1, queue)
		results.append(result)
	return results

func _attach(piece_id: int) -> void:
	var instance: AbilityInstance = AbilityInstance.new()
	instance.owner_id = piece_id
	instance.definition = EXPLOSION
	state.explosion.instances[piece_id] = instance
	state.explosion.unlocked = true

func _remove_and_enqueue(pieces: Array[PieceState], generation: int, queue: Array[BlastRequest]) -> void:
	for piece: PieceState in pieces:
		if state.rules.remove_piece(piece.piece_id) == null:
			continue
		var instance: AbilityInstance = state.explosion.instances.get(piece.piece_id)
		state.explosion.instances.erase(piece.piece_id)
		if instance == null or instance.has_triggered:
			continue
		instance.has_triggered = true
		var event: BlastRequest = BlastRequest.new()
		event.source = piece.copy()
		event.ability = instance
		event.generation = generation
		queue.append(event)

func _comes_before(a: BlastRequest, b: BlastRequest) -> bool:
	return a.generation < b.generation if a.generation != b.generation else a.source.piece_id < b.source.piece_id
