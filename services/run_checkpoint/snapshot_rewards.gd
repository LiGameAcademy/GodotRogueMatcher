extends RefCounted

## Restores frozen offers and target trees from trusted catalog IDs. Never freezes or draws again.
const V: Script = preload("res://services/run_checkpoint/snapshot_values.gd")

static func restore(run: RunController, data: Dictionary) -> bool:
	if data.is_empty(): return run.state.phase == RunState.Phase.INPUT
	if run.state.phase != RunState.Phase.REWARDS or run.state.pending_rewards <= 0: return false
	var catalog: Dictionary[StringName, SkillDefinition] = {}
	for skill: SkillDefinition in run.offer_catalog(): catalog[skill.skill_id] = skill
	var offer: SkillOffer = SkillOffer.new()
	if not V.scalars(offer, data, {"offer_id": "offer_id", "reward_id": "reward_id", "replaces_offer_id": "replaces_offer_id", "candidate_before": "candidate_state_before", "candidate_after": "candidate_state_after", "profile_id": "profile_id"}): return false
	if offer.reward_id != run.state.rewards.consumed_count + 1 or offer.offer_id < 1 or offer.offer_id >= run.state.rewards.next_offer_id: return false
	if offer.replaces_offer_id < 0 or offer.replaces_offer_id >= offer.offer_id: return false
	if run.state.rewards.repair_used != (offer.replaces_offer_id > 0): return false
	if not data.get("offer_rules_version") is String or data.offer_rules_version != SkillOfferGenerator.version_for_mode(run.state.mode_id()): return false
	offer.rules_version = data.offer_rules_version
	if not data.get("choices") is Array or data.choices.is_empty() or data.choices.size() > 3 or not data.get("targets") is Dictionary: return false
	for id: Variant in data.choices:
		if not id is String or not catalog.has(StringName(id)) or offer.targets.has(StringName(id)): return false
		var skill: SkillDefinition = catalog[StringName(id)]
		var frozen: Variant = data.targets.get(id)
		if not frozen is Dictionary or not V.integer(frozen.get("level_before"), 0, 1000000): return false
		# Partial invalidation keeps the originally frozen target/effect. Never retarget at restore.
		var target: SkillTarget = _target(frozen, skill.acquisition_effect(String(frozen.level_before).to_int()), 0)
		if target == null or target.level_after != target.level_before + 1: return false
		offer.choices.append(skill)
		offer.targets[skill.skill_id] = target
	if data.targets.size() != offer.choices.size(): return false
	if not data.get("generation_order") is Array or data.generation_order.size() != offer.choices.size(): return false
	for id: Variant in data.generation_order:
		if not id is String or not offer.targets.has(StringName(id)) or offer.generation_order.has(StringName(id)): return false
		offer.generation_order.append(StringName(id))
	for pair: Array in [["baseline_weights", offer.baseline_weights], ["weights", offer.weights]]:
		if not data.get(pair[0]) is Dictionary: return false
		for id: String in data[pair[0]]:
			var weight: Variant = data[pair[0]][id]
			if not catalog.has(StringName(id)) or not weight is float or not is_finite(weight) or weight < 0.0: return false
			pair[1][StringName(id)] = weight
	if not data.get("rescue_multiplier") is float or not is_finite(data.rescue_multiplier) or data.rescue_multiplier <= 0.0: return false
	offer.rescue_multiplier = data.rescue_multiplier
	for pair: Array in [["pressure_snapshot", "pressure_snapshot"], ["build_snapshot", "build_snapshot"], ["parameters", "parameter_snapshot"]]:
		if not data.get(pair[0]) is Dictionary: return false
		offer.set(pair[1], data[pair[0]].duplicate(true))
	if not data.get("explanations") is Dictionary or not data.get("unavailable") is Dictionary: return false
	for id: String in data.explanations:
		if not catalog.has(StringName(id)) or not data.explanations[id] is Dictionary: return false
		offer.explanations[StringName(id)] = data.explanations[id].duplicate(true)
	for id: String in data.unavailable:
		if not offer.targets.has(StringName(id)) or not data.unavailable[id] is String: return false
		offer.unavailable[StringName(id)] = data.unavailable[id]
	if not data.get("slots") is Array or not data.get("log") is Array: return false
	for slot: Variant in data.slots:
		if not slot is Dictionary: return false
		offer.slot_log.append(slot.duplicate(true))
	for item: Variant in data.log:
		if not item is String: return false
		offer.pool_log.append(item)
	run.state.rewards.active_offer = offer
	return true

static func _target(value: Variant, effect: SkillEffect, depth: int) -> SkillTarget:
	if not value is Dictionary or effect == null or depth > 32: return null
	var composite: bool = effect is CompositeEffect
	if composite != value.has("leaves"): return null
	var target: SkillTarget = CompositeSkillTarget.new() if composite else SkillTarget.new()
	if not V.scalars(target, value, {"deferred": "deferred", "color": "color", "line_axis": "line_axis", "line_index": "line_index", "level_before": "level_before", "level_after": "level_after", "before": "value_before", "after": "value_after", "remaining_before": "remaining_before", "remaining_after": "remaining_after"}): return null
	if not V.ints(value.get("coordinate"), -1, 63) or value.coordinate.size() != 2: return null
	target.coordinate = Vector2i(String(value.coordinate[0]).to_int(), String(value.coordinate[1]).to_int())
	for pair: Array in [["ids", target.piece_ids], ["cost_ids", target.cost_piece_ids], ["fuse_counts", target.fuse_counts]]:
		if not V.ints(value.get(pair[0]), 0): return null
		for id: String in value[pair[0]]: pair[1].append(id.to_int())
	if not value.get("color_groups") is Array: return null
	if composite:
		if not value.leaves is Array or value.leaves.size() != (effect as CompositeEffect).children.size(): return null
		for index: int in range(value.leaves.size()):
			var child: SkillTarget = _target(value.leaves[index], (effect as CompositeEffect).children[index], depth + 1)
			if child == null: return null
			(target as CompositeSkillTarget).leaf_targets.append(child)
		# Root picker groups are a projection of its leaf; never restore a second mutable copy.
	else:
		for group: Variant in value.color_groups:
			if not V.ints(group, 1): return null
			var ids: PackedInt64Array = PackedInt64Array()
			for id: String in group: ids.append(id.to_int())
			target.color_groups.append(ids)
	if target.deferred and not target.valid_deferred_contract(): return null
	if JSON.stringify(RunSnapshot.normalize(RunSnapshot.target_data(target)), "", true, true) != JSON.stringify(value, "", true, true): return null
	return target
