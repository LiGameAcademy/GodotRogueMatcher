class_name AbilityResolver
extends RefCounted

const DEFAULT_CONFIG: ExplosionConfig = preload("res://gameplay/skills/content/explosion_config.tres")
const EXPLOSION: AbilityDefinition = preload("res://gameplay/skills/content/on_eliminated_explosion.tres")

const LINE_SWEEP: AbilityDefinition = preload("res://gameplay/skills/content/on_eliminated_line_sweep.tres")

var state: RunState
var config: ExplosionConfig
var last_error: String = ""
var _held_blasts: Array[BlastRequest] = []
var _held_matches: Array[MatchResult] = []
var _held_plants: Array[FusePlantTrigger] = []
var _held_dyes: Array[DyeTrigger] = []

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
		_attach_line(piece.piece_id)
	return piece

## Validate the entire frozen batch before mutating any piece or installing an ability.
func transformation_error(ids: Array[int], content_id: StringName, costs: Array[int] = []) -> String:
	if content_id not in [&"special_demolition", LineClearState.CONTENT_ROW, LineClearState.CONTENT_COLUMN]:
		return "特殊棋转化类型无效"
	if ids.is_empty() or ids.size() > 3: return "转化目标数量无效"
	var seen: Array[int] = []
	for id: int in ids:
		var piece: PieceState = state.rules.state.get_piece(id)
		if piece == null or not piece.content_id.is_empty() or piece.is_ghost or seen.has(id) or state.explosion.instances.has(id) or state.line_clear.instances.has(id):
			return "原定转化目标已经失效"
		seen.append(id)
	for id: int in costs:
		var piece: PieceState = state.rules.state.get_piece(id)
		if piece == null or not piece.content_id.is_empty() or piece.is_ghost or seen.has(id) or state.explosion.instances.has(id) or state.line_clear.instances.has(id):
			return "原子转化成本已经失效"
		seen.append(id)
	return validation_error(1, ids.size() if content_id == &"special_demolition" else 0, 0, ids.size() if content_id != &"special_demolition" else 0)

## Conversion may install multiple cores; natural supply still uses add_core's singleton rule.
func transform_material(ids: Array[int], content_id: StringName, costs: Array[int] = []) -> Array[PieceState]:
	last_error = transformation_error(ids, content_id, costs)
	if not last_error.is_empty(): return []
	for id: int in costs:
		state.rules.remove_piece(id)
		state.dye.marks.erase(id)
	var transformed: Array[PieceState] = []
	for id: int in ids:
		state.rules.set_piece_content(id, content_id)
		if content_id == &"special_demolition": _attach(id)
		else: _attach_line(id)
		transformed.append(state.rules.state.get_piece(id))
	return transformed

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
func resolve(groups: Array[BoardMatchGroup], hold_descendants: bool = false) -> Array[MatchResult]:
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
	var dye: DyeTrigger = DyeRules.capture_matches(state, results)
	if hold_descendants:
		if dye != null: _held_dyes.append(dye)
		_held_blasts.append_array(queue)
		_held_matches.append_array(results)
		_plant_after_matches(results, true)
		return results
	_plant_after_matches(results)
	results.append_array(_resolve_blasts(queue))
	if dye != null:
		if not last_error.is_empty(): dye.cancel()
		else: results.append_array(dye.execute(self))
	return results

func _plant_after_matches(results: Array[MatchResult], hold: bool = false) -> void:
	var stats: DemolitionActionState = DemolitionRules.action(state)
	if state.explosion.level(&"fuse_match_plant") > 0 and not stats.plant_used:
		stats.plant_used = true
		var trigger: FusePlantTrigger = FusePlantTrigger.capture(results)
		if hold: _held_plants.append(trigger)
		else: trigger.execute(self)

## Clears and five-matches share removal triggers and the blast queue. Callers preflight before committing the root action.
## When hold_blasts is true, removal tickets enqueue but descendants wait for flush_held_blasts().
func resolve_removal(pieces: Array[PieceState], cause: StringName, hold_blasts: bool = false, score_cleared: bool = false) -> Array[MatchResult]:
	last_error = validation_error(1)
	if not last_error.is_empty(): return []
	if score_cleared:
		var live: Array[PieceState] = []
		var seen: Array[int] = []
		for piece: PieceState in pieces:
			var current: PieceState = state.rules.state.get_piece(piece.piece_id)
			if current == null or seen.has(piece.piece_id): continue
			seen.append(piece.piece_id)
			live.append(current.copy())
		pieces = live
	var queue: Array[BlastRequest] = []
	var results: Array[MatchResult] = []
	if score_cleared and not pieces.is_empty():
		var direct: MatchResult = MatchResult.new()
		direct.cause = cause
		direct.removed = pieces.duplicate()
		direct.center = pieces[pieces.size() / 2].coordinate
		direct.score_entry = _commit_clear_score(direct, true)
		results.append(direct)
	var extra: int = 0 if score_cleared else DemolitionRules.marked_score(state, pieces)
	_remove_and_enqueue(pieces, cause, 1, queue)
	if not last_error.is_empty(): return []
	if extra > 0:
		var reward: MatchResult = MatchResult.new()
		reward.cause = &"bonus"
		reward.score_entry = state.ledger.commit(0, 1.0, extra, &"marked_reward", DemolitionRules.root_id(state), [])
		results.append(reward)
	if hold_blasts:
		_held_blasts.append_array(queue)
		return results
	results.append_array(_resolve_blasts(queue))
	return results

## Drain blast tickets held during an ordered CompositeEffect.
func flush_held_blasts() -> Array[MatchResult]:
	if _held_blasts.is_empty() and _held_matches.is_empty(): return []
	var queue: Array[BlastRequest] = _held_blasts.duplicate()
	_held_blasts.clear()
	_held_matches.clear()
	var plants: Array[FusePlantTrigger] = _held_plants.duplicate()
	var dyes: Array[DyeTrigger] = _held_dyes.duplicate()
	_held_plants.clear()
	_held_dyes.clear()
	for trigger: FusePlantTrigger in plants: trigger.execute(self)
	var results: Array[MatchResult] = _resolve_blasts(queue)
	for trigger: DyeTrigger in dyes:
		if not last_error.is_empty(): trigger.cancel()
		else: results.append_array(trigger.execute(self))
	return results

## Drop held tickets without resolving blasts (composite aborted after removals).
func abandon_held_blasts() -> void:
	for event: BlastRequest in _held_blasts:
		if event.activation != null:
			state.ability_events.cancel(event.activation, &"composite_aborted")
	_held_blasts.clear()
	_held_matches.clear()
	for trigger: FusePlantTrigger in _held_plants: trigger.cancel()
	for trigger: DyeTrigger in _held_dyes: trigger.cancel()
	_held_plants.clear()
	_held_dyes.clear()

## Read-only recording projection; no resource or pending ticket references escape.
func pending_removals() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: BlastRequest in _held_blasts:
		result.append({"source": {"id": event.source.piece_id, "coordinate": event.source.coordinate,
			"color": event.source.match_color, "content_id": event.source.content_id}, "generation": event.generation,
			"event_id": event.activation.event.event_id, "strength": event.strength.data()})
	return result

func pending_followups() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trigger: FusePlantTrigger in _held_plants: result.append(trigger.trace.duplicate(true))
	for trigger: DyeTrigger in _held_dyes:
		result.append(trigger.trace.duplicate(true))
		for alternative: DyeTrigger in trigger.alternatives: result.append(alternative.trace.duplicate(true))
	return result

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
	var bridge: DyeTrigger = null
	var stats: DemolitionActionState = DemolitionRules.action(state)
	while not queue.is_empty():
		queue.sort_custom(_comes_before)
		var event: BlastRequest = queue.pop_front()
		if event.strength.line_sweep:
			results.append(_resolve_line_sweep(event, queue))
			if not last_error.is_empty():
				_cancel_blast_queue(queue, bridge, event)
				return results
		else:
			if event.strength.payload_count > 0:
				DemolitionRules.mark_near(self, [event.source.coordinate], event.strength.payload_radius, event.strength.payload_count)
			var request: BlastRequest = ExplodeEffect.new().build_request(state.rules.state, event.source, event.strength.radius)
			var result: MatchResult = MatchResult.new()
			result.cause = &"explosion"
			result.source_id = event.source.piece_id
			result.source_color = event.source.match_color
			result.center = event.source.coordinate
			result.radius = request.radius
			result.generation = event.generation
			result.trigger_strength = event.strength.data()
			var actual_ids: Array[int] = []
			for piece_id: int in request.target_ids:
				var target: PieceState = state.rules.state.get_piece(piece_id)
				if target == null: continue
				if event.strength.selective and target.match_color == event.source.match_color: continue
				result.removed.append(target)
				actual_ids.append(piece_id)
			var extra_score: int = 0
			if not result.removed.is_empty():
				stats.effective_blasts += 1
				stats.blast_removed += result.removed.size()
				if not event.synthetic and event.source.content_id == &"special_demolition" and stats.first_core == null:
					stats.first_core = event.source.copy()
				extra_score = event.strength.extra_score(state, result.removed)
			var ability_id: StringName = event.strength.ability_id
			result.score_entry = state.ledger.commit(0, 1.0, extra_score, &"explosion", DemolitionRules.root_id(state), actual_ids, result.source_id, ability_id)
			var parent_id: int = 0 if event.synthetic else event.activation.event.event_id
			_remove_and_enqueue(result.removed, result.cause, event.generation + 1, queue, parent_id, ability_id)
			if not event.synthetic:
				if not state.ability_events.complete(event.activation, true, result.removed.size()):
					_event_error("ability activation ticket invalid")
			if not last_error.is_empty():
				_cancel_blast_queue(queue, bridge, event)
				return results
			results.append(result)
			if bridge == null: bridge = DyeRules.capture_blast(state, result)
		# Append aftershock once after the normal queue drains; descendants cannot spawn another.
		if queue.is_empty() and stats.first_core != null and not stats.aftershock_used and state.explosion.level(&"blast_aftershock") > 0:
			stats.aftershock_used = true
			var aftershock: BlastRequest = BlastRequest.new()
			aftershock.source = stats.first_core.copy()
			aftershock.synthetic = true
			aftershock.generation = event.generation + 1
			aftershock.strength = RemovalStrength.capture(state, config, aftershock.source, aftershock.generation, EXPLOSION, true)
			queue.append(aftershock)
	if bridge != null: results.append_array(bridge.execute(self))
	return results

func _cancel_blast_queue(queue: Array[BlastRequest], bridge: DyeTrigger, failed: BlastRequest = null) -> void:
	if failed != null and failed.activation != null: state.ability_events.cancel(failed.activation, &"composite_aborted")
	for event: BlastRequest in queue:
		if event.activation != null: state.ability_events.cancel(event.activation, &"composite_aborted")
	queue.clear()
	if bridge != null: bridge.cancel()

## Sweeps use the ordinary score ledger, but are not five-match or blast skill triggers.
func _resolve_line_sweep(event: BlastRequest, queue: Array[BlastRequest]) -> MatchResult:
	var request: BlastRequest = LineSweepEffect.new().build_request(state.rules.state, event.source, event.strength.radius, event.strength.cross_radius)
	var result: MatchResult = MatchResult.new()
	result.cause = &"line_clear"
	result.line_axis = LineClearState.axis_of(event.source.content_id)
	result.radius = request.radius
	result.cross_radius = request.cross_radius
	result.source_id = event.source.piece_id
	result.source_color = event.source.match_color
	result.center = event.source.coordinate
	result.generation = event.generation
	result.trigger_strength = event.strength.data()
	for id: int in request.target_ids: result.removed.append(state.rules.state.get_piece(id))
	var ability_id: StringName = event.strength.ability_id
	var group: BoardMatchGroup = BoardMatchGroup.new()
	for piece: PieceState in result.removed: group.piece_ids.append(piece.piece_id)
	var multiplier: float = LegacyScoreModifiers.calculate(state.rules.state, group) + event.strength.multiplier_bonus
	result.score_entry = state.ledger.commit(result.removed.size(), multiplier, event.strength.extra_score(state, result.removed), result.cause, DemolitionRules.root_id(state), group.piece_ids, result.source_id, ability_id, true)
	_remove_and_enqueue(result.removed, result.cause, event.generation + 1, queue, event.activation.event.event_id, ability_id)
	if not state.ability_events.complete(event.activation, true, result.removed.size()):
		_event_error("ability activation ticket invalid")
	return result

## Common clear scoring; the caller distinguishes a scored skill clear from a five-match.
func _commit_clear_score(result: MatchResult, score_short_clear: bool = false, ability_id: StringName = &"") -> ScoreEntry:
	var ids: Array[int] = []
	for piece: PieceState in result.removed: ids.append(piece.piece_id)
	var group: BoardMatchGroup = BoardMatchGroup.new()
	group.piece_ids = ids
	var multiplier: float = LegacyScoreModifiers.calculate(state.rules.state, group) + state.explosion.multiplier_level * config.multiplier_per_level
	var extra: int = 0
	if not result.removed.is_empty():
		extra = state.explosion.match_extra_level * config.bonus_per_match + DemolitionRules.marked_score(state, result.removed) + DyeRules.match_score(state, ids)
		if result.cause == &"line_clear": extra += LineClearRules.score_bonus(state.line_clear, result.removed.size())
	return state.ledger.commit(result.removed.size(), multiplier, extra, result.cause, DemolitionRules.root_id(state), ids, result.source_id, ability_id, score_short_clear)

func _attach_line(piece_id: int) -> void:
	var instance: AbilityInstance = AbilityInstance.new()
	instance.owner_id = piece_id
	instance.definition = LINE_SWEEP
	state.line_clear.instances[piece_id] = instance

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
		event.strength = RemovalStrength.capture(state, config, event.source, generation, activation.instance.definition)
		queue.append(event)
	if not state.ability_events.last_error.is_empty(): _event_error(state.ability_events.last_error)

## Internal errors after preflight terminate explicitly; already committed results are not pretended to roll back.
func _event_error(reason: String) -> void:
	last_error = reason
	state.rule_error = reason
	state.phase = RunState.Phase.ERROR

func _comes_before(a: BlastRequest, b: BlastRequest) -> bool:
	return a.generation < b.generation if a.generation != b.generation else a.source.piece_id < b.source.piece_id
