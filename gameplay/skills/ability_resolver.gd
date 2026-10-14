class_name AbilityResolver
extends RefCounted

const DEFAULT_CONFIG: ExplosionConfig = preload("res://gameplay/skills/content/explosion_config.tres")
const EXPLOSION: AbilityDefinition = preload("res://gameplay/skills/content/on_eliminated_explosion.tres")

const LINE_SWEEP: AbilityDefinition = preload("res://gameplay/skills/content/on_eliminated_line_sweep.tres")

var state: RunState
var config: ExplosionConfig
var last_error: String = ""
var _held_blasts: Array[BlastRequest] = []

func _init(run_state: RunState, rules_config: ExplosionConfig = DEFAULT_CONFIG) -> void:
	state = run_state
	config = rules_config

## Place a core and attach its removal-blast instance; reject if a core already exists.
func add_core(coordinate: Vector2i, match_color: int = -1) -> PieceState:
	for piece: PieceState in state.rules.state.get_snapshot():
		if piece.content_id == &"special_demolition":
			return null
	# Natural refill passes the previewed color; skill summons and teaching samples keep config defaults.
	var color: int = config.core_color if match_color == -1 else match_color
	var core: PieceState = state.rules.place_piece(coordinate, color, &"special_demolition")
	if core != null:
		_attach(core.piece_id)
	return core

## Multiple sweepers may coexist; each owns one innate removal activation.
func add_line_piece(axis: int, coordinate: Vector2i, match_color: int = -1) -> PieceState:
	if axis != LineClearState.AXIS_ROW and axis != LineClearState.AXIS_COLUMN: return null
	var color: int = LineClearRules.CONFIG.default_color if match_color == -1 else match_color
	var piece: PieceState = state.rules.place_piece(coordinate, color, state.line_clear.content_id(axis))
	if piece != null:
		var instance: AbilityInstance = AbilityInstance.new()
		instance.owner_id = piece.piece_id
		instance.definition = LINE_SWEEP
		state.line_clear.instances[piece.piece_id] = instance
	return piece

## Install a fuse on a normal piece; reject if it already has content or an instance.
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

## Same-generation order is by source id; descendants run only after the current generation finishes. No UI or animation dependency.
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
		if not last_error.is_empty(): return results
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

## Clears and five-matches share removal triggers and the blast queue. Callers preflight before committing the root action.
## When hold_blasts is true, removal tickets enqueue but descendants wait for flush_held_blasts().
func resolve_removal(pieces: Array[PieceState], cause: StringName, hold_blasts: bool = false) -> Array[MatchResult]:
	last_error = validation_error(1)
	if not last_error.is_empty(): return []
	var queue: Array[BlastRequest] = []
	var extra: int = DemolitionRules.marked_score(state, pieces)
	_remove_and_enqueue(pieces, cause, 1, queue)
	if not last_error.is_empty(): return []
	var results: Array[MatchResult] = []
	if extra > 0:
		var reward: MatchResult = MatchResult.new()
		reward.cause = &"bonus"
		reward.score_entry = state.ledger.commit(0, 1.0, extra, &"marked_reward", DemolitionRules.root_id(state), [])
		results.append(reward)
	if hold_blasts:
		_held_blasts.append_array(queue)
		return results
	results.append_array(_resolve_blasts(queue))
	results.append_array(DyeRules.after_matches(self, results))
	return results

## Drain blast tickets held during an ordered CompositeEffect.
func flush_held_blasts() -> Array[MatchResult]:
	if _held_blasts.is_empty(): return []
	var queue: Array[BlastRequest] = _held_blasts.duplicate()
	_held_blasts.clear()
	var results: Array[MatchResult] = _resolve_blasts(queue)
	results.append_array(DyeRules.after_matches(self, results))
	return results

## Drop held tickets without resolving blasts (composite aborted after removals).
func abandon_held_blasts() -> void:
	for event: BlastRequest in _held_blasts:
		if event.activation != null:
			state.ability_events.complete(event.activation, false, 0)
	_held_blasts.clear()

## Preflight configuration and event budget before resolve; return an English diagnostic on failure.
func validation_error(root_events: int, new_sources: int = 0, new_pieces: int = 0, new_line_sources: int = 0) -> String:
	if new_sources > 0:
		var configuration_error: String = AbilityTriggerAdapter.validation_error(EXPLOSION)
		if not configuration_error.is_empty(): return configuration_error
	if new_line_sources > 0:
		var configuration_error: String = AbilityTriggerAdapter.validation_error(LINE_SWEEP)
		if not configuration_error.is_empty(): return configuration_error
	# Config errors and budget shortfalls must reject before any occupancy or score commit.
	for instance: AbilityInstance in state.explosion.instances.values() + state.line_clear.instances.values():
		var error: String = AbilityTriggerAdapter.validation_error(instance.definition)
		if not error.is_empty(): return error
	var possible: int = state.explosion.instances.size() + state.line_clear.instances.size() + new_sources + new_line_sources
	if state.explosion.level(&"core_fuse_payload") > 0 or state.explosion.level(&"fuse_match_plant") > 0:
		possible = state.rules.state.get_piece_count() + new_pieces
	if state.explosion.level(&"blast_aftershock") > 0: possible += 1
	if root_events + possible > config.event_budget:
		return "event budget exceeded; resolve rejected"
	return ""

func _resolve_blasts(queue: Array[BlastRequest]) -> Array[MatchResult]:
	var results: Array[MatchResult] = []
	var stats: DemolitionActionState = DemolitionRules.action(state)
	while not queue.is_empty():
		queue.sort_custom(_comes_before)
		var event: BlastRequest = queue.pop_front()
		if not event.synthetic and event.ability.definition.effect is LineSweepEffect:
			results.append(_resolve_line_sweep(event, queue))
			if not last_error.is_empty(): return results
		else:
			if not event.synthetic and event.source.content_id == &"special_demolition" and state.explosion.level(&"core_fuse_payload") > 0:
				DemolitionRules.mark_near(self, [event.source.coordinate], DemolitionRules.CONFIG.payload_radius, DemolitionRules.CONFIG.payload_count)
			var radius: int = DemolitionRules.CONFIG.aftershock_radius if event.synthetic else DemolitionRules.radius(state, event.source, event.generation, config.base_radius)
			var effect: ExplodeEffect = (EXPLOSION.effect if event.synthetic else event.ability.definition.effect) as ExplodeEffect
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
			var parent_id: int = 0 if event.synthetic else event.activation.event.event_id
			_remove_and_enqueue(result.removed, result.cause, event.generation + 1, queue, parent_id, ability_id)
			if not event.synthetic:
				if not state.ability_events.complete(event.activation, true, result.removed.size()):
					_event_error("ability activation ticket invalid")
			if not last_error.is_empty(): return results
			results.append(result)
		# Append aftershock once after the normal queue drains; descendants cannot spawn another.
		if queue.is_empty() and stats.first_core != null and not stats.aftershock_used and state.explosion.level(&"blast_aftershock") > 0:
			stats.aftershock_used = true
			var aftershock: BlastRequest = BlastRequest.new()
			aftershock.source = stats.first_core.copy()
			aftershock.synthetic = true
			aftershock.generation = event.generation + 1
			queue.append(aftershock)
	results.append_array(DyeRules.after_blasts(self, results))
	return results

## Sweeps use the ordinary score ledger, but are not five-match or blast skill triggers.
func _resolve_line_sweep(event: BlastRequest, queue: Array[BlastRequest]) -> MatchResult:
	var effect: LineSweepEffect = event.ability.definition.effect as LineSweepEffect
	var request: BlastRequest = effect.build_request(state.rules.state, event.source)
	var result: MatchResult = MatchResult.new()
	result.cause = &"line_clear"
	result.line_axis = LineClearState.axis_of(event.source.content_id)
	result.source_id = event.source.piece_id
	result.source_color = event.source.match_color
	result.center = event.source.coordinate
	result.generation = event.generation
	for id: int in request.target_ids: result.removed.append(state.rules.state.get_piece(id))
	var group: BoardMatchGroup = BoardMatchGroup.new()
	group.piece_ids = request.target_ids
	var multiplier: float = LegacyScoreModifiers.calculate(state.rules.state, group) + state.explosion.multiplier_level * config.multiplier_per_level
	var extra: int = 0
	if not result.removed.is_empty():
		extra = state.explosion.match_extra_level * config.bonus_per_match + DemolitionRules.marked_score(state, result.removed) + DyeRules.match_score(state, request.target_ids)
	var ability_id: StringName = event.ability.definition.ability_id
	result.score_entry = state.ledger.commit(result.removed.size(), multiplier, extra, result.cause, DemolitionRules.root_id(state), request.target_ids, result.source_id, ability_id)
	_remove_and_enqueue(result.removed, result.cause, event.generation + 1, queue, event.activation.event.event_id, ability_id)
	if not state.ability_events.complete(event.activation, true, result.removed.size()):
		_event_error("ability activation ticket invalid")
	return result

func _attach(piece_id: int) -> void:
	var instance: AbilityInstance = AbilityInstance.new()
	instance.owner_id = piece_id
	instance.definition = EXPLOSION
	state.explosion.instances[piece_id] = instance
	state.explosion.unlocked = true

func _remove_and_enqueue(pieces: Array[PieceState], cause: StringName, generation: int, queue: Array[BlastRequest], parent_id: int = 0, source_ability: StringName = &"") -> void:
	var events: Array[AbilityEvent] = []
	var listeners: Array[AbilityInstance] = []
	for piece: PieceState in pieces:
		if state.rules.remove_piece(piece.piece_id) == null:
			continue
		state.dye.marks.erase(piece.piece_id)
		var instance: AbilityInstance = state.explosion.instances.get(piece.piece_id)
		state.explosion.instances.erase(piece.piece_id)
		if instance == null: instance = state.line_clear.instances.get(piece.piece_id)
		state.line_clear.instances.erase(piece.piece_id)
		if instance == null:
			continue
		listeners.append(instance)
		events.append(state.ability_events.removal(piece, cause, DemolitionRules.root_id(state), generation, state.run_id, parent_id, source_ability))
	# Dispatch after the whole removal batch; removed instances subscribe only for this batch and use frozen sources.
	for activation: AbilityActivation in state.ability_events.dispatch(events, listeners):
		var event: BlastRequest = BlastRequest.new()
		event.source = activation.event.source.copy()
		event.ability = activation.instance
		event.activation = activation
		event.generation = generation
		queue.append(event)
	if not state.ability_events.last_error.is_empty(): _event_error(state.ability_events.last_error)

## Internal errors after preflight terminate explicitly; already committed results are not pretended to roll back.
func _event_error(reason: String) -> void:
	last_error = reason
	state.rule_error = reason
	state.phase = RunState.Phase.ERROR

func _comes_before(a: BlastRequest, b: BlastRequest) -> bool:
	return a.generation < b.generation if a.generation != b.generation else a.source.piece_id < b.source.piece_id
