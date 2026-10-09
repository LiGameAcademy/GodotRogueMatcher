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
	last_error = validation_error(groups.size())
	if not last_error.is_empty(): return results
	var queue: Array[BlastRequest] = []
	var global_multiplier: float = state.explosion.multiplier_level * config.multiplier_per_level
	for group: BoardMatchGroup in groups:
		var result: MatchResult = MatchResult.new()
		for piece_id: int in group.piece_ids:
			result.removed.append(state.rules.state.get_piece(piece_id))
		result.center = result.removed[result.removed.size() / 2].coordinate
		result.score_entry = state.ledger.commit(group.piece_ids.size(), LegacyScoreModifiers.calculate(state.rules.state, group) + global_multiplier, state.explosion.match_extra_level * config.bonus_per_match + DemolitionRules.match_score(state, group.piece_ids.size()) + DemolitionRules.marked_score(state, result.removed) + DyeRules.match_score(state, group.piece_ids), &"match", DemolitionRules.root_id(state), group.piece_ids)
		results.append(result)
	for result: MatchResult in results:
		_remove_and_enqueue(result.removed, result.cause, 1, queue)
	var stats: DemolitionActionState = DemolitionRules.action(state)
	if state.explosion.level(&"fuse_match_plant") > 0 and not stats.plant_used:
		stats.plant_used = true
		var centers: Array[Vector2i] = []
		for result: MatchResult in results:
			for piece: PieceState in result.removed: centers.append(piece.coordinate)
		DemolitionRules.mark_near(self, centers, DemolitionRules.CONFIG.plant_radius, DemolitionRules.CONFIG.plant_count)
	results.append_array(_resolve_blasts(queue))
	results.append_array(DyeRules.after_matches(self, results))
	return results

## 清理与五连共用离场触发和爆炸队列。调用者在提交根行动前预检。
func resolve_removal(pieces: Array[PieceState], cause: StringName) -> Array[MatchResult]:
	last_error = validation_error(1)
	if not last_error.is_empty(): return []
	var queue: Array[BlastRequest] = []
	var extra: int = DemolitionRules.marked_score(state, pieces)
	_remove_and_enqueue(pieces, cause, 1, queue)
	var results: Array[MatchResult] = []
	if extra > 0:
		var reward: MatchResult = MatchResult.new()
		reward.cause = &"bonus"
		reward.score_entry = state.ledger.commit(0, 1.0, extra, &"marked_reward", DemolitionRules.root_id(state), [])
		results.append(reward)
	results.append_array(_resolve_blasts(queue))
	results.append_array(DyeRules.after_matches(self, results))
	return results

func validation_error(root_events: int, new_sources: int = 0, new_pieces: int = 0) -> String:
	if new_sources > 0:
		var configuration_error: String = AbilityTriggerAdapter.validation_error(EXPLOSION)
		if not configuration_error.is_empty(): return configuration_error
	# 配置错误、预算不足必须在任何占格/计分提交前拒绝。
	for instance: AbilityInstance in state.explosion.instances.values():
		var error: String = AbilityTriggerAdapter.validation_error(instance.definition)
		if not error.is_empty(): return error
	var possible: int = state.explosion.instances.size() + new_sources
	if state.explosion.level(&"core_fuse_payload") > 0 or state.explosion.level(&"fuse_match_plant") > 0:
		possible = state.rules.state.get_piece_count() + new_pieces
	if state.explosion.level(&"blast_aftershock") > 0: possible += 1
	if root_events + possible > config.event_budget:
		return "事件预算不足，拒绝结算"
	return ""

func _resolve_blasts(queue: Array[BlastRequest]) -> Array[MatchResult]:
	var results: Array[MatchResult] = []
	var stats: DemolitionActionState = DemolitionRules.action(state)
	while not queue.is_empty():
		queue.sort_custom(_comes_before)
		var event: BlastRequest = queue.pop_front()
		if not event.synthetic and event.source.content_id == &"special_demolition" and state.explosion.level(&"core_fuse_payload") > 0:
			DemolitionRules.mark_near(self, [event.source.coordinate], DemolitionRules.CONFIG.payload_radius, DemolitionRules.CONFIG.payload_count)
		var radius: int = DemolitionRules.CONFIG.aftershock_radius if event.synthetic else DemolitionRules.radius(state, event.source, event.generation, config.base_radius)
		var effect: ExplodeEffect = EXPLOSION.effect if event.synthetic else event.ability.definition.effect
		var request: BlastRequest = effect.build_request(state.rules.state, event.source, radius)
		var result: MatchResult = MatchResult.new()
		result.cause = &"explosion"
		result.source_id = event.source.piece_id
		result.source_color = event.source.match_color
		result.center = event.source.coordinate
		result.radius = request.radius
		result.generation = event.generation
		var actual_ids: Array[int] = []
		for piece_id: int in request.target_ids:
			var target: PieceState = state.rules.state.get_piece(piece_id)
			if target == null: continue
			if state.explosion.level(&"selective_blast") > 0 and target.match_color == event.source.match_color: continue
			result.removed.append(target)
			actual_ids.append(piece_id)
		var extra_score: int = 0
		if not result.removed.is_empty():
			stats.effective_blasts += 1
			stats.blast_removed += result.removed.size()
			if not event.synthetic and event.source.content_id == &"special_demolition" and stats.first_core == null:
				stats.first_core = event.source.copy()
			extra_score = result.removed.size() * state.explosion.reward_level * config.reward_per_target + state.explosion.blast_extra_level * config.bonus_per_blast
			extra_score += DemolitionRules.marked_score(state, result.removed)
			if event.generation >= 2:
				extra_score += DemolitionRules.CONFIG.chain_bonus * state.explosion.level(&"blast_chain_bonus") * mini(event.generation - 1, DemolitionRules.CONFIG.chain_depth_cap)
		var ability_id: StringName = &"blast_aftershock" if event.synthetic else event.ability.definition.ability_id
		result.score_entry = state.ledger.commit(0, 1.0, extra_score, &"explosion", DemolitionRules.root_id(state), actual_ids, result.source_id, ability_id)
		_remove_and_enqueue(result.removed, result.cause, event.generation + 1, queue)
		results.append(result)
		# 普通队列收束后只追加一次，后代不能再次制造余震。
		if queue.is_empty() and stats.first_core != null and not stats.aftershock_used and state.explosion.level(&"blast_aftershock") > 0:
			stats.aftershock_used = true
			var aftershock: BlastRequest = BlastRequest.new()
			aftershock.source = stats.first_core.copy()
			aftershock.synthetic = true
			aftershock.generation = event.generation + 1
			queue.append(aftershock)
	results.append_array(DyeRules.after_blasts(self, results))
	return results

func _attach(piece_id: int) -> void:
	var instance: AbilityInstance = AbilityInstance.new()
	instance.owner_id = piece_id
	instance.definition = EXPLOSION
	state.explosion.instances[piece_id] = instance
	state.explosion.unlocked = true

func _remove_and_enqueue(pieces: Array[PieceState], cause: StringName, generation: int, queue: Array[BlastRequest]) -> void:
	for piece: PieceState in pieces:
		if state.rules.remove_piece(piece.piece_id) == null:
			continue
		state.dye.marks.erase(piece.piece_id)
		var instance: AbilityInstance = state.explosion.instances.get(piece.piece_id)
		state.explosion.instances.erase(piece.piece_id)
		if instance == null:
			continue
		var trigger_event: AbilityEvent = AbilityEvent.new()
		trigger_event.cause = cause
		trigger_event.source = piece.copy()
		trigger_event.root_action_id = DemolitionRules.root_id(state)
		trigger_event.generation = generation
		if not AbilityTriggerAdapter.try_accept(instance, trigger_event): continue
		var event: BlastRequest = BlastRequest.new()
		event.source = piece.copy()
		event.ability = instance
		event.generation = generation
		queue.append(event)

func _comes_before(a: BlastRequest, b: BlastRequest) -> bool:
	return a.generation < b.generation if a.generation != b.generation else a.source.piece_id < b.source.piece_id
