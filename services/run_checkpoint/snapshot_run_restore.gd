extends RefCounted

## Cold safe-point restore, including frozen offers and stages. No initialize/effects/history replay.
## Normal runs only; prototype shapes and the live save entry point remain outside this slice.
const V: Script = preload("res://services/run_checkpoint/snapshot_values.gd")
const REWARDS: Script = preload("res://services/run_checkpoint/snapshot_rewards.gd")
const STAGES: Script = preload("res://services/run_checkpoint/snapshot_stages.gd")
const ENTITIES: Script = preload("res://services/run_checkpoint/snapshot_entities.gd")

static func project(run: RunController) -> Dictionary:
	var state: Dictionary = RunSnapshot.capture(run, false)
	state.erase("ledger")
	# A cold dispatcher has a new scope. Only its next ID crosses the process boundary;
	# old event objects cannot pass the scope check, so their dispatched set is history.
	state.ability_events.dispatched = []
	# Past scoring entries are presentation history. A new action sets its own entry cursor.
	if run.state.stage.enabled() and run.state.stage.root_action_id != run.state.stage.settled_root_id:
		state.challenge.action_score = str(run.state.stage.action_score + run.state.ledger.unsettled_stage_score(run.state.stage.entry_offset, run.state.stage.root_action_id, StageState.SCORE_REASONS))
	state.challenge.entry_offset = "0"
	if state.challenge.history.size() > 1: state.challenge.history = [state.challenge.history.back()]
	if run.state.rewards.active_offer != null:
		state.offer["profile_id"] = String(run.state.rewards.active_offer.profile_id)
		state.offer["unavailable"] = RunSnapshot.normalize(run.state.rewards.active_offer.unavailable)
	return state

static func restore(state: Dictionary, seed: int, run_id: String, board: Dictionary, stage_config: StageConfig = null) -> Dictionary:
	if not V.keys(board, PackedStringArray(["columns", "rows", "match_count"])): return _failure("snapshot_state_invalid")
	if not V.integer(board.columns, 1, 64) or not V.integer(board.rows, 1, 64) or not V.integer(board.match_count, 2, 128): return _failure("snapshot_state_invalid")
	var rules: BoardRules = BoardRules.new(BoardState.new(String(board.columns).to_int(), String(board.rows).to_int()), String(board.match_count).to_int())
	var run: RunController = RunController.new(rules, seed, stage_config)
	run.state.run_id = run_id
	var required: PackedStringArray = PackedStringArray(project(run).keys())
	if not V.keys(state, required): return _failure("snapshot_state_invalid")
	for key: String in ["spawning", "demolition", "line_clear", "dye", "challenge", "ability_events", "shape_unlocks", "acquired", "manual_uses_used", "offer"]:
		if not state[key] is Dictionary: return _failure("snapshot_state_invalid")
	for key: String in ["pieces", "instances", "skills", "levels", "history", "pending_removals", "pending_followups", "random"]:
		if not state[key] is Array: return _failure("snapshot_state_invalid")
	if not V.integer(state.phase, 1, 3) or not state.continuation is String or not V.integer(state.pending, 0, 1000000): return _failure("snapshot_state_invalid")
	if not state.game_over is bool or state.game_over or state.error != "" or state.end_reason != "": return _failure("snapshot_state_invalid")
	if not state.pending_removals.is_empty() or not state.pending_followups.is_empty(): return _failure("snapshot_state_invalid")
	if not state.demolition.get("roots") is Array: return _failure("snapshot_unsettled_roots")
	if not state.challenge.get("enabled") is bool: return _failure("snapshot_state_invalid")
	var streams: RunRandomStreams = RunRandomStreams.from_data(state.rng)
	if streams == null or streams.master_seed != seed: return _failure("snapshot_state_invalid")
	run.state.random_streams = streams
	run.state.random = streams.stream(&"spawn_position")
	run.state.rewards = RewardState.new(seed, streams)
	run.state.spawning = SpawnState.new(RunController.SPAWN_CONFIG, seed, streams.stream(&"spawn_content"))
	if not V.integer(state.last_command, 0) or not state.direct_match is bool: return _failure("snapshot_state_invalid")
	if not run.restore_checkpoint_command(String(state.last_command).to_int(), state.direct_match): return _failure("snapshot_state_invalid")
	run.continuation = StringName(state.continuation)
	if not _scalars(run, state): return _failure("snapshot_scalars_invalid")
	if not _maps(run, state): return _failure("snapshot_maps_invalid")
	if not ENTITIES.pieces(run, state.pieces, state.next_piece_id): return _failure("snapshot_state_invalid")
	if not ENTITIES.skills(run, state.skills, state.acquired): return _failure("snapshot_skills_invalid")
	if not ENTITIES.innate_abilities(run, state.instances): return _failure("snapshot_innate_invalid")
	if not run.state.explosion.instances.is_empty() and not run.state.explosion.unlocked: return _failure("snapshot_innate_invalid")
	if not ENTITIES.spawn_plan(run, state.spawning): return _failure("snapshot_spawning_invalid")
	if not ENTITIES.roots(run, state.demolition.roots): return _failure("snapshot_roots_invalid")
	if not _events(run, state.ability_events) or not _shapes(run, state.shape_unlocks): return _failure("snapshot_state_invalid")
	if not STAGES.restore(run, state.challenge) or not REWARDS.restore(run, state.offer): return _failure("snapshot_state_invalid")
	if not RunCheckpointCodec.safety_error(run).is_empty(): return _failure("snapshot_state_invalid")
	# Also rejects omitted/extra nested fields and redundant RNG/definition values that disagree.
	var restored: Dictionary = project(run)
	if JSON.stringify(restored, "", true, true) != JSON.stringify(state, "", true, true):
		for key: String in state:
			if JSON.stringify(restored.get(key), "", true, true) != JSON.stringify(state[key], "", true, true): return _failure("snapshot_roundtrip:" + key)
		return _failure("snapshot_roundtrip:structure")
	return {"ok": true, "reason": "", "run": run}

static func _scalars(run: RunController, value: Dictionary) -> bool:
	var state: RunState = run.state
	if not V.scalars(state, value, {"phase": "phase", "turn": "turn_count", "action": "action_id", "moves": "valid_moves", "pending": "pending_rewards", "goal_bonus_score": "goal_bonus_score"}): return false
	if state.turn_count < 1 or state.action_id < 0 or state.valid_moves < 0 or state.valid_moves > state.action_id or state.goal_bonus_score < 0: return false
	if not V.integer(value.total, 0) or not V.integer(value.next_event_id, 1): return false
	if not state.ledger.restore_checkpoint(String(value.total).to_int(), String(value.next_event_id).to_int()): return false
	if not V.scalars(state.progression, value, {"milestone_level": "level", "previous_milestone": "previous_milestone", "next_milestone": "next_milestone"}): return false
	if state.progression.level < 0 or state.progression.previous_milestone < 0 or state.progression.next_milestone <= state.progression.previous_milestone: return false
	if not state.stage.enabled() and not _progression(state): return false
	if not V.scalars(state.rewards, value, {"consumed": "consumed_count", "next_offer_id": "next_offer_id", "reward_repair_used": "repair_used"}): return false
	if state.rewards.consumed_count < 0 or state.rewards.next_offer_id < 1: return false
	if not state.stage.enabled() and state.rewards.consumed_count + state.pending_rewards != state.progression.level: return false
	if state.rewards.next_offer_id <= state.rewards.consumed_count: return false
	if not V.scalars(run, value, {"action_refill_count": "action_refill_count"}): return false
	if run.action_refill_count < 0 or run.action_refill_count > 1024: return false
	var demolition: Dictionary = value.demolition
	if not V.scalars(state, demolition, {"rule_action_id": "rule_action_id", "activations": "activations"}): return false
	if state.activations < 0 or state.valid_moves + state.activations > state.action_id: return false
	if not V.scalars(run, demolition, {"turn_action_id": "turn_action_id"}): return false
	if not V.scalars(state.explosion, demolition, {"core_pool": "core_pool_unlocked", "fuse_unlocked": "fuse_unlocked"}): return false
	if not value.levels is Array or value.levels.size() != 5 or not V.ints(value.levels, 0, 1000000) or not value.unlocked is bool: return false
	state.explosion.unlocked = value.unlocked
	var properties: Array[String] = ["radius_level", "reward_level", "multiplier_level", "match_extra_level", "blast_extra_level"]
	for index: int in range(properties.size()): state.explosion.set(properties[index], String(value.levels[index]).to_int())
	if not V.scalars(state.line_clear, value.line_clear, {"row": "row_unlocked", "column": "column_unlocked"}): return false
	if not V.scalars(state.dye, value.dye, {"root": "root_id", "waves": "waves_used", "match": "considered_match", "blast": "considered_blast", "chain": "allow_chain"}): return false
	if state.dye.waves_used < 0 or not V.ints(value.dye.get("ids"), 1): return false
	for id: String in value.dye.ids: state.dye.dyed_ids.append(id.to_int())
	return true

static func _maps(run: RunController, value: Dictionary) -> bool:
	for data: Variant in [value.acquired, value.manual_uses_used, value.demolition.get("upgrades"), value.line_clear.get("upgrades"), value.dye.get("upgrades"), value.dye.get("marks")]:
		if not V.int_map(data): return false
	var allowed: Dictionary = {"explosion": {}, "line": {}, "dye": {}}
	var catalog: Dictionary[StringName, SkillDefinition] = {}
	for definition: SkillDefinition in run.offer_catalog():
		catalog[definition.skill_id] = definition
		if definition.levels.is_empty(): _upgrade_ids(definition.choice_effect, allowed)
		else:
			for level: SkillLevelDefinition in definition.levels:
				for ability: AbilityDefinition in level.abilities: _upgrade_ids(ability.effect, allowed)
	for pair: Array in [[value.demolition.upgrades, allowed.explosion], [value.line_clear.upgrades, allowed.line], [value.dye.upgrades, allowed.dye]]:
		for key: String in pair[0]:
			if not pair[1].has(key): return false
	run.state.explosion.upgrades = V.names(value.demolition.upgrades)
	run.state.line_clear.upgrades = V.names(value.line_clear.upgrades)
	run.state.dye.upgrades = V.names(value.dye.upgrades)
	for key: String in value.manual_uses_used:
		if not catalog.has(StringName(key)) or catalog[StringName(key)].manual_use_limit <= 0: return false
	run.state.manual_uses_used = V.names(value.manual_uses_used)
	for key: String in value.dye.marks:
		if not V.integer(key, 1): return false
		run.state.dye.marks[key.to_int()] = String(value.dye.marks[key]).to_int()
	for id: Variant in value.history:
		if not id is String or not catalog.has(StringName(id)): return false
		run.state.rewards.previous_unselected.append(StringName(id))
	if not value.demolition.get("roots") is Array: return false
	return true

static func _upgrade_ids(effect: Resource, output: Dictionary) -> void:
	if effect is CompositeEffect:
		for child: SkillEffect in (effect as CompositeEffect).children: _upgrade_ids(child, output)
	elif effect is InstallUpgradeEffect: output.explosion[String((effect as InstallUpgradeEffect).upgrade)] = true
	elif effect is InstallLineUpgradeEffect: output.line[String((effect as InstallLineUpgradeEffect).upgrade)] = true
	elif effect is InstallDyeUpgradeEffect: output.dye[String((effect as InstallDyeUpgradeEffect).upgrade)] = true

static func _events(run: RunController, value: Dictionary) -> bool:
	if not V.keys(value, PackedStringArray(["next_event_id", "dispatched", "active"])) or not value.active is bool or not value.active: return false
	if not V.integer(value.next_event_id, 1) or not V.ints(value.dispatched, 1): return false
	if not value.dispatched.is_empty(): return false
	var ids: Array[int] = []
	for id: String in value.dispatched: ids.append(id.to_int())
	return run.state.ability_events.restore_checkpoint(String(value.next_event_id).to_int(), ids)

static func _shapes(run: RunController, value: Dictionary) -> bool:
	if not value.get("enabled") is Array or not value.enabled.is_empty(): return false
	if value.get("recovery_pending") != false or value.get("recovery_attempted") != false: return false
	return V.scalars(run.state.rules.shape_unlocks, value, {"recovery_pending": "recovery_pending", "recovery_attempted": "recovery_attempted", "recovery_root": "recovery_root", "recovery_batch_id": "recovery_batch_id", "recovery_action_id": "recovery_action_id"})

static func _progression(state: RunState) -> bool:
	# Current classic configuration reaches the int64 score boundary well before 128 levels.
	# Bound corrupt counters before calling the iterative threshold rule; never repair them.
	if state.progression.level > 128: return false
	var previous: int = 0
	var current: int = 0
	for index: int in range(state.progression.level + 1):
		previous = current
		if index < RunController.PROGRESSION.milestones.size(): current = RunController.PROGRESSION.milestones[index]
		else:
			var next: float = ceil(current * RunController.PROGRESSION.tail_multiplier)
			if next >= float(9223372036854775807) or current == 9223372036854775807: return false
			current = maxi(current + 1, int(next))
	var configured: int = RunController.PROGRESSION.threshold(state.progression.level)
	var configured_previous: int = RunController.PROGRESSION.threshold(state.progression.level - 1) if state.progression.level > 0 else 0
	return state.progression.previous_milestone == configured_previous and state.progression.next_milestone == configured and state.ledger.total >= previous and state.ledger.total < current

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
