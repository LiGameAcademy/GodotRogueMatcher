extends RefCounted

## Builds detached board entities and skill instances from stable definitions; executes no effects.
const V: Script = preload("res://services/run_checkpoint/snapshot_values.gd")

static func pieces(run: RunController, values: Array, next_id: Variant) -> bool:
	if not V.integer(next_id, 1): return false
	var restored: Array[PieceState] = []
	for value: Variant in values:
		var piece: PieceState = piece_from(value)
		if piece == null: return false
		restored.append(piece)
	return run.state.rules.state.restore_checkpoint(restored, String(next_id).to_int())

static func piece_from(value: Variant) -> PieceState:
	if not V.keys(value, PackedStringArray(["id", "coordinate", "color", "content_id", "ghost"])): return null
	if not V.integer(value.id, 1) or not V.integer(value.color, 0, 4) or not value.ghost is bool: return null
	if not value.coordinate is Array or value.coordinate.size() != 2 or not V.ints(value.coordinate, 0, 63): return null
	if value.content_id not in ["", "special_demolition", "special_line_row", "special_line_column"]: return null
	var piece: PieceState = PieceState.new()
	piece.piece_id = String(value.id).to_int()
	piece.coordinate = Vector2i(String(value.coordinate[0]).to_int(), String(value.coordinate[1]).to_int())
	piece.match_color = String(value.color).to_int()
	piece.content_id = StringName(value.content_id)
	piece.is_ghost = value.ghost
	return piece

static func skills(run: RunController, values: Array, acquired: Dictionary) -> bool:
	var catalog: Dictionary[StringName, SkillDefinition] = {}
	for definition: SkillDefinition in run.offer_catalog(): catalog[definition.skill_id] = definition
	for id: String in acquired:
		if not catalog.has(StringName(id)) or not V.integer(acquired[id], 1, 1000000): return false
	var ids: Dictionary[int, bool] = {}
	for value: Variant in values:
		if not V.keys(value, PackedStringArray(["instance_id", "skill_id", "level", "abilities"])): return false
		if not value.skill_id is String or not catalog.has(StringName(value.skill_id)): return false
		var definition: SkillDefinition = catalog[StringName(value.skill_id)]
		if not V.integer(value.instance_id, 1, run.state.rewards.consumed_count) or not V.integer(value.level, 1, definition.levels.size()): return false
		var id: int = String(value.instance_id).to_int()
		if ids.has(id) or run.state.skill_instances.has(definition.skill_id): return false
		ids[id] = true
		var level: int = String(value.level).to_int()
		if acquired.get(value.skill_id) != value.level or not value.abilities is Array: return false
		var instance: SkillInstance = SkillInstance.new(definition, id)
		instance.level = level
		var definitions: Array[AbilityDefinition] = definition.levels[level - 1].abilities
		if definitions.size() != value.abilities.size(): return false
		for index: int in range(definitions.size()):
			var data: Variant = value.abilities[index]
			var ability: AbilityInstance = AbilityInstance.new()
			ability.definition = definitions[index]
			ability.skill_instance_id = id
			if not data is Dictionary or data.get("ability_id") != String(ability.definition.ability_id) or data.get("event_type") != String(ability.definition.event_type): return false
			if not V.scalars(ability, data, {"trigger_count": "trigger_count", "pending_event_id": "pending_event_id"}): return false
			if ability.trigger_count < 0 or ability.pending_event_id != 0: return false
			instance.abilities.append(ability)
		run.state.skill_instances[definition.skill_id] = instance
	var count: int = 0
	for key: String in acquired:
		var definition: SkillDefinition = catalog[StringName(key)]
		if not definition.levels.is_empty() and not run.state.skill_instances.has(definition.skill_id): return false
		var amount: int = String(acquired[key]).to_int()
		if amount > run.state.rewards.consumed_count - count: return false
		count += amount
	if count != run.state.rewards.consumed_count: return false
	run.state.rewards.acquired = V.names(acquired)
	return true

static func innate_abilities(run: RunController, values: Array) -> bool:
	var seen: Dictionary[int, bool] = {}
	for value: Variant in values:
		if not value is Dictionary or not V.integer(value.get("id"), 1): return false
		var id: int = String(value.id).to_int()
		var piece: PieceState = run.state.rules.state.get_piece(id)
		if piece == null or seen.has(id): return false
		seen[id] = true
		var line: bool = LineClearState.is_line_piece(piece.content_id)
		var definition: AbilityDefinition = AbilityResolver.LINE_SWEEP if line else AbilityResolver.EXPLOSION
		if not line and piece.content_id not in [&"", &"special_demolition"]: return false
		if value.get("ability") != String(definition.ability_id) or value.get("owner_id") != value.id: return false
		var ability: AbilityInstance = AbilityInstance.new()
		ability.definition = definition
		ability.owner_id = id
		if not V.scalars(ability, value, {"skill_instance_id": "skill_instance_id", "trigger_count": "trigger_count", "pending_event_id": "pending_event_id"}): return false
		if ability.skill_instance_id != 0 or ability.trigger_count < 0 or ability.pending_event_id != 0: return false
		if line: run.state.line_clear.instances[id] = ability
		else: run.state.explosion.instances[id] = ability
	for piece: PieceState in run.state.rules.state.get_snapshot():
		if not piece.content_id.is_empty() and not seen.has(piece.piece_id): return false
	return true

static func spawn_plan(run: RunController, data: Dictionary) -> bool:
	if not V.ints(data.get("color_weights"), 0, 1000000) or data.color_weights.size() != 5: return false
	if not data.get("refill_batches") is Dictionary or not V.keys(data.refill_batches, PackedStringArray(["-1", "1"])): return false
	if not V.integer(data.refill_batches["-1"], 0) or not V.integer(data.refill_batches["1"], 0): return false
	var sum: int = 0
	run.state.spawning.color_weights.clear()
	for weight: String in data.color_weights:
		run.state.spawning.color_weights.append(weight.to_int())
		sum += weight.to_int()
	if sum <= 0 or not data.get("plan") is Array or data.plan.size() > 1024: return false
	run.state.spawning.refill_batches = {-1: String(data.refill_batches["-1"]).to_int(), 1: String(data.refill_batches["1"]).to_int()}
	var plan: Array[SpawnToken] = []
	for value: Variant in data.plan:
		if not V.keys(value, PackedStringArray(["color", "core_candidate", "core_color", "line_axis"])): return false
		if not V.integer(value.color, 0, 4) or not V.integer(value.core_color, 0, 4) or not V.integer(value.line_axis, -1, 1) or not value.core_candidate is bool: return false
		if value.core_candidate and value.line_axis != "-1": return false
		plan.append(SpawnToken.new(String(value.color).to_int(), value.core_candidate, String(value.core_color).to_int(), String(value.line_axis).to_int()))
	return run.state.spawning.restore_checkpoint_plan(plan)

static func roots(run: RunController, values: Array) -> bool:
	for value: Variant in values:
		if not V.keys(value, PackedStringArray(["id", "plant", "aftershock", "effective_blasts", "removed", "core"])): return false
		if not V.integer(value.id, -1, run.state.action_id) or not value.core is Dictionary: return false
		var id: int = String(value.id).to_int()
		if run.state.explosion.actions.has(id): return false
		var root: DemolitionActionState = DemolitionActionState.new()
		if not V.scalars(root, value, {"plant": "plant_used", "aftershock": "aftershock_used", "effective_blasts": "effective_blasts", "removed": "blast_removed"}): return false
		if root.effective_blasts < 0 or root.blast_removed < 0: return false
		if not value.core.is_empty():
			root.first_core = piece_from(value.core)
			if root.first_core == null: return false
		run.state.explosion.actions[id] = root
	return true
