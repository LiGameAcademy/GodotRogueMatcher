extends GutTest

## Safe-point snapshots preserve frozen choices, unfinished stage attribution and independent segments.
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const RESTORE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
const SEGMENT: Script = preload("res://services/run_checkpoint/snapshot_segment.gd")

func _run(stage: bool = false) -> RunController:
	var config: StageConfig = null
	if stage:
		config = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
		config.targets = [1, 1, 1, 1, 1, 1, 1, 1]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, config)
	run.initialize()
	return run

func _reward(run: RunController, bot: GreedyBot) -> bool:
	for index: int in range(350):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): return false
		if run.state.rewards.active_offer != null: return true
		if run.state.phase == RunState.Phase.INPUT:
			var command: RunCommand = bot.choose(run)
			if command == null or not run.execute_command(command).accepted: return false
		else: run.advance()
	return false

func _restore(run: RunController) -> Dictionary:
	var before: Dictionary = RESTORE.project(run)
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	assert_true(frozen.ok, frozen.reason)
	if not frozen.ok: return frozen
	var encoded: Dictionary = SNAPSHOT.serialize(frozen.payload)
	assert_true(encoded.ok, encoded.reason)
	if not encoded.ok: return encoded
	var parsed: Dictionary = SNAPSHOT.deserialize(encoded.bytes)
	assert_true(parsed.ok, parsed.reason)
	if not parsed.ok: return parsed
	var result: Dictionary = SNAPSHOT.decode(parsed.data, SNAPSHOT.manifest(run))
	assert_true(result.ok, result.reason)
	assert_eq(before, RESTORE.project(run), "source unchanged")
	if result.ok:
		assert_eq(before, RESTORE.project(result.run))
		assert_eq(run.state.random_streams.data(), result.run.state.random_streams.data())
	return result

func _follow(a: RunController, b: RunController, bot: GreedyBot, count: int = 5) -> void:
	var accepted: int = 0
	for index: int in range(100):
		assert_eq(RESTORE.project(a), RESTORE.project(b), "same continuation")
		if a.state.is_game_over: break
		if a.state.phase == RunState.Phase.INPUT or a.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(a)
			assert_not_null(command)
			if command == null: return
			var copy: RunCommand = CommandCodec.decode(CommandCodec.encode(command))
			assert_eq(a.execute_command(command).accepted, b.execute_command(copy).accepted)
			accepted += 1
		else:
			a.advance()
			b.advance()
		if accepted >= count: break
	assert_eq(accepted, count)
	assert_eq(RESTORE.project(a), RESTORE.project(b))

func test_classic_frozen_group_rng_targets_and_same_next_commands() -> void:
	var run: RunController = _run()
	var bot: GreedyBot = GreedyBot.new(100023)
	assert_true(_reward(run, bot))
	var restored: Dictionary = _restore(run)
	if not restored.ok: return
	var offer: SkillOffer = run.state.rewards.active_offer
	assert_ne(offer, restored.run.state.rewards.active_offer)
	for id: StringName in offer.targets: assert_ne(offer.targets[id], restored.run.state.rewards.active_offer.targets[id])
	_follow(run, restored.run, bot)

func test_stage_reward_preserves_original_refill_and_starts_next_once() -> void:
	var run: RunController = _run(true)
	var bot: GreedyBot = GreedyBot.new(100023)
	assert_true(_reward(run, bot))
	assert_true(run.state.stage.awaiting_reward)
	var restored: Dictionary = _restore(run)
	if not restored.ok: return
	assert_ne(run.state.stage.config, restored.run.state.stage.config)
	_follow(run, restored.run, bot)

func test_stage_input_and_following_eight_commands_preserve_stage_attribution() -> void:
	var run: RunController = _run(true)
	# A normal stage mode cannot open a reward before settlement, but its INPUT snapshot
	# must preserve an already settled stage and the next action's attribution exactly.
	var bot: GreedyBot = GreedyBot.new(100023)
	var restored: Dictionary = _restore(run)
	if restored.ok: _follow(run, restored.run, bot, 8)

func test_rehashed_bad_offer_and_stage_fields_reject_without_rng_or_source_changes() -> void:
	var run: RunController = _run(true)
	assert_true(_reward(run, GreedyBot.new(100023)))
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	var before: Dictionary = RESTORE.project(run)
	for field: String in frozen.payload.state.offer:
		var bad: Dictionary = frozen.payload.duplicate(true)
		bad.state.offer[field] = null
		bad.state_hash = RunSnapshot.digest(bad.state)
		assert_false(SNAPSHOT.decode(bad, SNAPSHOT.manifest(run)).ok, field)
	for field: String in frozen.payload.state.challenge:
		var bad: Dictionary = frozen.payload.duplicate(true)
		bad.state.challenge[field] = null
		bad.state_hash = RunSnapshot.digest(bad.state)
		assert_false(SNAPSHOT.decode(bad, SNAPSHOT.manifest(run)).ok, field)
	assert_eq(before, RESTORE.project(run))

func test_snapshot_segment_is_not_opening_header_and_replays_only_new_tail() -> void:
	var source: RunController = _run(true)
	var bot: GreedyBot = GreedyBot.new(100023)
	assert_true(_reward(source, bot))
	var loaded: Dictionary = _restore(source)
	if not loaded.ok: return
	var run: RunController = loaded.run
	var started: Dictionary = SEGMENT.begin(run, "snapshot-segment-a")
	assert_true(started.ok, started.reason)
	if not started.ok: return
	assert_false(started.lineage_known)
	assert_eq(run.recorder.records[0].kind, "SnapshotHeader")
	assert_false(RuleReplay.new().restore_prefix(run.recorder.records))
	for index: int in range(4):
		if run.state.phase == RunState.Phase.INPUT or run.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(run)
			assert_not_null(command)
			if command == null: return
			assert_true(run.execute_command(command).accepted)
		else: run.advance()
	var checked: Dictionary = SEGMENT.replay(run.recorder.records, SNAPSHOT.manifest(run))
	assert_true(checked.ok, checked.reason)
	if checked.ok:
		assert_false(checked.whole_run_replay)
		var persisted: Array[Dictionary] = []
		for row: Dictionary in run.recorder.records: persisted.append(JSON.parse_string(JSON.stringify(row, "", true, true)))
		var roundtrip: Dictionary = SEGMENT.replay(persisted, SNAPSHOT.manifest(run))
		assert_true(roundtrip.ok, "actual JSONL representation: " + roundtrip.reason)
		assert_eq(RESTORE.project(run), RESTORE.project(checked.run))
	for invalid: Variant in [null, [], "bad"]:
		var malformed: Array[Dictionary] = run.recorder.records.duplicate(true)
		malformed[0].metadata = invalid
		assert_false(SEGMENT.replay(malformed, SNAPSHOT.manifest(run)).ok)
	var bad: Array[Dictionary] = run.recorder.records.duplicate(true)
	bad[0].snapshot.state.pending = "999"
	bad[0].snapshot.state_hash = RunSnapshot.digest(bad[0].snapshot.state)
	assert_false(SEGMENT.replay(bad, SNAPSHOT.manifest(run)).ok)
func test_frozen_continuation_vectors_and_partial_groups_keep_identity_and_once_only_choice() -> void:
	var original: RunController = _run()
	assert_true(_reward(original, GreedyBot.new(100023)))
	for position: StringName in [&"idle", &"before_end", &"after_end", &"after_spawn"]:
		for size: int in [1, 2, 3]:
			var frozen: Dictionary = SNAPSHOT.freeze(original)
			var candidate: Dictionary = SNAPSHOT.decode(frozen.payload, SNAPSHOT.manifest(original))
			assert_true(candidate.ok, candidate.reason)
			if not candidate.ok: return
			var run: RunController = candidate.run
			run.continuation = position
			var offer: SkillOffer = run.state.rewards.active_offer
			while offer.choices.size() > size:
				var removed: SkillDefinition = offer.choices.pop_back()
				offer.targets.erase(removed.skill_id)
				offer.generation_order.erase(removed.skill_id)
			# Controlled legal safe-point vectors; does not claim all positions occur in seed23.
			var loaded: Dictionary = _restore(run)
			if not loaded.ok: return
			var command: RunCommand = GreedyBot.new(100023).choose(run)
			var copy: RunCommand = CommandCodec.decode(CommandCodec.encode(command))
			assert_true(run.execute_command(command).accepted)
			assert_true(loaded.run.execute_command(copy).accepted)
			var consumed: int = loaded.run.state.rewards.consumed_count
			loaded.run.execute_command(copy)
			assert_eq(loaded.run.state.rewards.consumed_count, consumed, "duplicate consumes once")
			assert_eq(RESTORE.project(run), RESTORE.project(loaded.run))
			_follow(run, loaded.run, GreedyBot.new(100024), 2)

func test_stage_unsettled_score_materialization_counts_current_root_only() -> void:
	var run: RunController = _run(true)
	# A controlled unfinished root checks the state normalization independently of reward timing.
	run.state.action_id = 1
	run.state.stage.begin_action(1, 0)
	run.state.ledger.commit(5, 1.0, 0, &"match", 1)
	run.state.ledger.commit(5, 1.0, 0, &"match", 0)
	run.continuation = &"before_end"
	var projected: Dictionary = RESTORE.project(run)
	assert_eq(projected.challenge.action_score, "50")
	assert_eq(projected.challenge.entry_offset, "0")
	assert_false(projected.has("ledger"))
func test_frozen_target_nested_types_and_effect_tree_mismatch_are_rejected() -> void:
	var run: RunController = _run()
	assert_true(_reward(run, GreedyBot.new(100023)))
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	for id: String in frozen.payload.state.offer.targets:
		for field: String in frozen.payload.state.offer.targets[id]:
			var bad: Dictionary = frozen.payload.duplicate(true)
			bad.state.offer.targets[id][field] = null
			bad.state_hash = RunSnapshot.digest(bad.state)
			assert_false(SNAPSHOT.decode(bad, SNAPSHOT.manifest(run)).ok, id + ":" + field)
func test_completed_stage_continue_reward_restores_continuing_flag_and_next_stage_once() -> void:
	var run: RunController = _run(true)
	var bot: GreedyBot = GreedyBot.new(100023)
	for index: int in range(500):
		if run.state.is_game_over: break
		if run.state.phase == RunState.Phase.INPUT or run.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(run)
			if command == null: break
			run.execute_command(command)
		else: run.advance()
	assert_true(run.can_continue_challenge(), String(run.state.end_reason))
	if not run.can_continue_challenge(): return
	assert_false(SNAPSHOT.freeze(run).ok, "completed terminal itself is not resumable")
	var next: ContinueChallengeCommand = ContinueChallengeCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	assert_true(run.execute_command(next).accepted)
	run.prepare_offer()
	assert_true(run.state.stage.continuing)
	var loaded: Dictionary = _restore(run)
	if loaded.ok: _follow(run, loaded.run, bot, 3)

func test_ro07_snapshot_before_and_after_real_offer_repair_preserves_quota_and_old_identity() -> void:
	var run: RunController = _run()
	assert_true(_reward(run, GreedyBot.new(100023)))
	var core: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([core])
	# Restrict this controlled legal-pool vector; no production catalog/config mutation.
	run.state.rewards.active_offer = null
	var original: SkillOffer = run.prepare_offer(false, generator)
	assert_not_null(original)
	if original == null: return
	var before_repair: Dictionary = _restore(run)
	if not before_repair.ok: return
	assert_not_null(run.state.rules.place_piece(original.targets[core.skill_id].coordinate, 0))
	assert_not_null(before_repair.run.state.rules.place_piece(original.targets[core.skill_id].coordinate, 0))
	var replacement: SkillOffer = run.prepare_offer(false, generator)
	assert_not_null(before_repair.run.prepare_offer(false, generator))
	assert_not_null(replacement)
	if replacement == null: return
	assert_eq(RESTORE.project(run), RESTORE.project(before_repair.run), "first repair after restore matches source")
	assert_eq(replacement.replaces_offer_id, original.offer_id)
	assert_true(run.state.rewards.repair_used)
	var loaded: Dictionary = _restore(run)
	if not loaded.ok: return
	var old: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	old.reward_id = original.reward_id
	old.offer_id = original.offer_id
	old.skill_id = core.skill_id
	var before: Dictionary = RESTORE.project(loaded.run)
	assert_false(loaded.run.execute_command(old).accepted)
	# Rejected fresh commands still consume their sequence ID by the existing command contract.
	assert_eq(loaded.run.last_command_id, old.command_id)
	before.last_command = str(old.command_id)
	assert_eq(before, RESTORE.project(loaded.run))
	assert_not_null(loaded.run.state.rules.place_piece(replacement.targets[core.skill_id].coordinate, 1))
	var rng: Dictionary = loaded.run.state.random_streams.data()
	var next_id: int = loaded.run.state.rewards.next_offer_id
	assert_null(loaded.run.prepare_offer(false, generator))
	assert_eq(loaded.run.state.rule_error, "reward_repair_already_used")
	assert_eq(loaded.run.state.rewards.next_offer_id, next_id)
	assert_eq(loaded.run.state.random_streams.data(), rng)
	assert_false(SNAPSHOT.freeze(loaded.run).ok)
