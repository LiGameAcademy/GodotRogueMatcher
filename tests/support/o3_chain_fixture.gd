extends RefCounted
## Bounded O3 B2/L2 causality fixtures. Not natural acquisition, supply continuity, or balance samples.

const F: Script = preload("res://tests/support/o3_fixed_fixture.gd")
const MANUAL: SkillDefinition = preload("res://gameplay/progression/content/line_manual_clear.tres")
const CROSS: SkillDefinition = preload("res://gameplay/progression/content/line_cross_upgrade.tres")
const DETONATE: SkillDefinition = preload("res://gameplay/progression/content/core_manual_detonation.tres")

static func _install(run: RunController, skill: SkillDefinition) -> void:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	assert(result.success, result.error)

static func blast_chain(seed_value: int, effective: bool) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialization = "o3_custom_b2"
	run.state.run_id = "fixture-o3-b2-%d-%s" % [seed_value, str(effective)]
	run.state.explosion.core_pool_unlocked = true
	run.state.explosion.fuse_unlocked = true
	_install(run, DETONATE)
	var core: PieceState = run.abilities.add_core(Vector2i(2, 2))
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(3, 2), 0)
	assert(run.abilities.assign_fuse(fuse.piece_id))
	var neighbor_ids: Array[int] = []
	if effective:
		for coordinate: Vector2i in [Vector2i(4, 2), Vector2i(3, 3)]:
			neighbor_ids.append(run.state.rules.place_piece(coordinate, posmod(coordinate.x + coordinate.y, 5)).piece_id)
	run.start_turn()
	var before: Dictionary = F.observe(run)
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, 1, run.state.action_id)
	command.source = "fixture"
	command.piece_id = core.piece_id
	var response: CommandResult = run.execute_command(command)
	var matches: Array[Dictionary] = []
	if response.turn != null: matches = RunRecorder.matches(response.turn.matches)
	var steps: Array[Dictionary] = []
	if response.accepted: steps = F.settle(run)
	return {"source": "fixture/automated", "route": "B2", "seed": str(seed_value), "effective": effective,
		"rules_version": RunSnapshot.RULES_VERSION, "fuse_id": fuse.piece_id, "core_id": core.piece_id,
		"neighbor_ids": neighbor_ids, "before": before, "accepted": response.accepted, "reason": response.reason,
		"matches": matches, "generations": _generation_rows(matches), "steps": steps, "final": F.observe(run),
		"traces": run.state.ability_events.take_traces()}

static func cross_sweep(seed_value: int, with_cross: bool) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialization = "o3_custom_l2"
	run.state.run_id = "fixture-o3-l2-%d-%s" % [seed_value, str(with_cross)]
	run.state.line_clear.row_unlocked = true
	run.state.line_clear.column_unlocked = true
	var source: PieceState = run.abilities.add_line_piece(0, Vector2i(4, 4), 0)
	var row_ids: Array[int] = []
	var exclusive_ids: Array[int] = []
	for coordinate: Vector2i in [Vector2i(5, 4), Vector2i(6, 4)]:
		row_ids.append(run.state.rules.place_piece(coordinate, 1).piece_id)
	for coordinate: Vector2i in [Vector2i(4, 5), Vector2i(4, 6)]:
		exclusive_ids.append(run.state.rules.place_piece(coordinate, 2).piece_id)
	_install(run, MANUAL)
	if with_cross: _install(run, CROSS)
	run.start_turn()
	var before: Dictionary = F.observe(run)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.source = "fixture"
	command.piece_id = source.piece_id
	var response: CommandResult = run.execute_command(command)
	var matches: Array[Dictionary] = []
	if response.turn != null: matches = RunRecorder.matches(response.turn.matches)
	var steps: Array[Dictionary] = []
	if response.accepted: steps = F.settle(run)
	var primary: Dictionary = matches[0] if not matches.is_empty() else {}
	var removed_ids: Array[int] = []
	for piece_data: Dictionary in primary.get("removed", []):
		removed_ids.append(int(piece_data.id))
	var exclusive_hits: int = 0
	for piece_id: int in exclusive_ids:
		if removed_ids.has(piece_id): exclusive_hits += 1
	var row_hits: int = 0
	for piece_id: int in row_ids:
		if removed_ids.has(piece_id): row_hits += 1
	return {"source": "fixture/automated", "route": "L2", "seed": str(seed_value), "with_cross": with_cross,
		"rules_version": RunSnapshot.RULES_VERSION, "source_id": source.piece_id, "row_ids": row_ids,
		"exclusive_ids": exclusive_ids, "before": before, "accepted": response.accepted, "reason": response.reason,
		"matches": matches, "row_hits": row_hits, "exclusive_hits": exclusive_hits,
		"radius": primary.get("radius", ""), "cross_radius": primary.get("cross_radius", ""),
		"steps": steps, "final": F.observe(run)}

static func _generation_rows(matches: Array[Dictionary]) -> Array[Dictionary]:
	var generations: Array[Dictionary] = []
	for match_data: Dictionary in matches:
		generations.append({"generation": match_data.generation, "cause": match_data.cause,
			"source_id": match_data.source_id, "removed": (match_data.removed as Array).size(),
			"score": match_data.score})
	return generations

static func _has_cause(matches: Array[Dictionary], cause: String) -> bool:
	for match_data: Dictionary in matches:
		if str(match_data.cause) == cause: return true
	return false

## M1: core blast removes a line carrier that then sweeps live targets (or misses the carrier).
static func blast_starts_line(seed_value: int, hit_line: bool) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialization = "o3_custom_m1"
	run.state.run_id = "fixture-o3-m1-%d-%s" % [seed_value, str(hit_line)]
	run.state.explosion.core_pool_unlocked = true
	run.state.line_clear.row_unlocked = true
	var choices_before: int = run.state.rewards.consumed_count
	_install(run, DETONATE)
	var core: PieceState = run.abilities.add_core(Vector2i(2, 2))
	var line: PieceState = run.abilities.add_line_piece(0, Vector2i(3, 2) if hit_line else Vector2i(7, 7), 0)
	var sweep_ids: Array[int] = []
	if hit_line:
		for coordinate: Vector2i in [Vector2i(4, 2), Vector2i(5, 2)]:
			sweep_ids.append(run.state.rules.place_piece(coordinate, 1).piece_id)
	else:
		run.state.rules.place_piece(Vector2i(3, 2), 2)
	run.start_turn()
	var before: Dictionary = F.observe(run)
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, 1, run.state.action_id)
	command.source = "fixture"
	command.piece_id = core.piece_id
	var response: CommandResult = run.execute_command(command)
	var matches: Array[Dictionary] = []
	if response.turn != null: matches = RunRecorder.matches(response.turn.matches)
	var steps: Array[Dictionary] = []
	if response.accepted: steps = F.settle(run)
	var sweep_hits: int = 0
	for match_data: Dictionary in matches:
		if str(match_data.cause) != "line_clear": continue
		for piece_data: Dictionary in match_data.removed:
			if sweep_ids.has(int(piece_data.id)): sweep_hits += 1
	return {"source": "fixture/automated", "route": "M1", "seed": str(seed_value), "hit_line": hit_line,
		"rules_version": RunSnapshot.RULES_VERSION, "core_id": core.piece_id, "line_id": line.piece_id,
		"sweep_ids": sweep_ids, "choices_consumed": run.state.rewards.consumed_count - choices_before,
		"before": before, "accepted": response.accepted, "reason": response.reason, "matches": matches,
		"generations": _generation_rows(matches), "has_line_clear": _has_cause(matches, "line_clear"),
		"sweep_hits": sweep_hits, "steps": steps, "final": F.observe(run),
		"traces": run.state.ability_events.take_traces()}

## M2: manual line removes a core that then blasts (effective hit or empty descendant).
static func line_starts_blast(seed_value: int, effective: bool) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialization = "o3_custom_m2"
	run.state.run_id = "fixture-o3-m2-%d-%s" % [seed_value, str(effective)]
	run.state.explosion.core_pool_unlocked = true
	run.state.line_clear.row_unlocked = true
	var choices_before: int = run.state.rewards.consumed_count
	_install(run, MANUAL)
	var line: PieceState = run.abilities.add_line_piece(0, Vector2i(2, 4), 0)
	var core: PieceState = run.abilities.add_core(Vector2i(5, 4))
	var blast_ids: Array[int] = []
	if effective:
		# Keep blast targets off the swept row so line-clear does not consume them first.
		for coordinate: Vector2i in [Vector2i(5, 3), Vector2i(5, 5)]:
			blast_ids.append(run.state.rules.place_piece(coordinate, posmod(coordinate.y, 5)).piece_id)
	run.abilities.upgrade_reward()
	run.start_turn()
	var before: Dictionary = F.observe(run)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.source = "fixture"
	command.piece_id = line.piece_id
	var response: CommandResult = run.execute_command(command)
	var matches: Array[Dictionary] = []
	if response.turn != null: matches = RunRecorder.matches(response.turn.matches)
	var steps: Array[Dictionary] = []
	if response.accepted: steps = F.settle(run)
	var blast_removed: int = 0
	var blast_hits: int = 0
	for match_data: Dictionary in matches:
		if str(match_data.cause) == "line_clear": continue
		blast_removed += (match_data.removed as Array).size()
		for piece_data: Dictionary in match_data.removed:
			if blast_ids.has(int(piece_data.id)): blast_hits += 1
	return {"source": "fixture/automated", "route": "M2", "seed": str(seed_value), "effective": effective,
		"rules_version": RunSnapshot.RULES_VERSION, "line_id": line.piece_id, "core_id": core.piece_id,
		"blast_ids": blast_ids, "choices_consumed": run.state.rewards.consumed_count - choices_before,
		"before": before, "accepted": response.accepted, "reason": response.reason, "matches": matches,
		"generations": _generation_rows(matches), "has_line_clear": _has_cause(matches, "line_clear"),
		"blast_removed": blast_removed, "blast_hits": blast_hits, "steps": steps, "final": F.observe(run),
		"traces": run.state.ability_events.take_traces()}

static func shipped_cross_replay(seed_value: int = 101) -> Dictionary:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialize("fixture_line_cross")
	run.recorder = RunRecorder.new()
	run.recorder.metadata = {"collection_context": "fixture", "purpose": "O3 L2 shipped cross chain"}
	run.recorder.begin(run, "fixture", false)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.source = "fixture"
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(2, 4))
	var response: CommandResult = run.execute_command(command)
	var steps: Array[Dictionary] = []
	if response.accepted: steps = F.settle(run)
	run.recorder.finish(run, "censored", "tool_limit")
	assert(F.write_records("l2-shipped-cross", run.recorder.records) == OK)
	var replay: RuleReplay = RuleReplay.new()
	var ok: bool = replay.replay_file(F.evidence_path("l2-shipped-cross", "jsonl"))
	return {"source": "fixture/automated", "route": "L2", "fixture": "fixture_line_cross",
		"accepted": response.accepted, "reason": response.reason,
		"matches": RunRecorder.matches(response.turn.matches) if response.turn != null else [],
		"score": run.state.ledger.total, "steps": steps, "record_file": "l2-shipped-cross.jsonl",
		"replay_ok": ok, "replay_error": replay.error, "replay_complete": replay.complete,
		"checked_records": replay.checked_records}
