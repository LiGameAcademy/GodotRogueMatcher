extends GutTest

## Exercises the formal payload through real rules and isolated FileAccess slots.
const SHAPES: Script = preload("res://tests/support/shape_unlock_fixture.gd")
class FailingFiles extends CheckpointFiles:
	var fail_primary: bool = false

	func replace(source: String, destination: String) -> Error:
		if fail_primary and source.get_file() == "checkpoint.tmp": return ERR_CANT_CREATE
		return super.replace(source, destination)

var _directories: Array[String] = []

func after_each() -> void:
	for directory: String in _directories:
		if not DirAccess.dir_exists_absolute(directory): continue
		for name: String in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(name))
		DirAccess.remove_absolute(directory)
	_directories.clear()

func _directory() -> String:
	var path: String = "user://checkpoint-restore-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.append(path)
	return path

func _normal(seed_value: int = 7) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialize()
	_record(run)
	return run

func _record(run: RunController) -> void:
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_test", false)

func _reward() -> RunController:
	var config: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
	config.targets = [1, 150, 200, 300, 400, 550, 750, 1000]
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23, config)
	run.initialize("fixture_f6")
	_record(run)
	var move: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	move.piece_id = run.state.rules.state.get_piece_id(Vector2i(5, 5))
	move.target = Vector2i(5, 4)
	run.execute_command(move)
	for index: int in range(20):
		if run.state.rewards.active_offer != null: return run
		run.advance()
	return run

func _same(first: RunController, second: RunController) -> void:
	assert_eq(first.state.run_id, second.state.run_id)
	assert_eq(RunSnapshot.capture(first), RunSnapshot.capture(second))
	assert_eq(first.state.random_streams.data(), second.state.random_streams.data())

func _settle(run: RunController) -> void:
	for index: int in range(20):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): return
		if run.state.phase == RunState.Phase.INPUT and run.continuation == &"idle": return
		if run.state.rewards.active_offer != null: return
		run.advance()

func test_input_payload_roundtrips_max_seed_and_isolates_object_graph() -> void:
	var run: RunController = _normal(9223372036854775807)
	var before: Dictionary = RunSnapshot.capture(run)
	var count: int = run.recorder.records.size()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	assert_true(encoded.ok, encoded.reason)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(encoded.payload))
	var restored: Dictionary = RunCheckpointCodec.decode(parsed, encoded.manifest)
	assert_true(restored.ok, restored.reason)
	if not restored.ok: return
	_same(run, restored.run)
	assert_ne(run, restored.run)
	assert_ne(run.state.rules.state, restored.run.state.rules.state)
	assert_ne(run.state.ledger, restored.run.state.ledger)
	assert_eq(run.recorder.records.size(), count)
	assert_eq(RunSnapshot.capture(run), before)
	assert_eq(parsed.master_seed, "9223372036854775807")
	assert_same(restored.run.state.random, restored.run.state.random_streams.stream(&"spawn_position"))
	assert_same(restored.run.state.rewards.target_random, restored.run.state.random_streams.stream(&"offer_targets"))
	assert_same(restored.run.state.rewards.candidate_random, restored.run.state.random_streams.stream(&"offer_candidates"))
	assert_same(restored.run.state.rewards.display_random, restored.run.state.random_streams.stream(&"offer_order"))
	assert_same(restored.run.state.spawning.content_random, restored.run.state.random_streams.stream(&"spawn_content"))
	var piece: PieceState = restored.run.state.rules.state.get_snapshot()[0]
	restored.run.state.rules.remove_piece(piece.piece_id)
	assert_eq(RunSnapshot.capture(run), before)
	assert_eq(parsed.state, before)

func test_input_restore_continues_multiple_identical_commands_and_preserves_retry_cache() -> void:
	var run: RunController = _normal()
	var bot: RandomLegalBot = RandomLegalBot.new(41)
	var first: RunCommand = bot.choose(run)
	assert_true(run.execute_command(first).accepted)
	_settle(run)
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	assert_true(encoded.ok, encoded.reason)
	var restored: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest)
	assert_true(restored.ok, restored.reason)
	if not restored.ok: return
	var other: RunController = restored.run
	var before: Dictionary = RunSnapshot.capture(other)
	assert_true(other.execute_command(first).accepted)
	assert_eq(RunSnapshot.capture(other), before)
	_same(run, other)
	for index: int in range(4):
		var command: RunCommand = bot.choose(run)
		assert_not_null(command)
		if command == null: return
		assert_eq(run.execute_command(command).accepted, other.execute_command(command).accepted)
		_settle(run)
		_settle(other)
		_same(run, other)
		if run.state.rewards.active_offer != null: return

func test_frozen_reward_keeps_candidates_targets_stage_plan_and_consumes_once() -> void:
	var run: RunController = _reward()
	assert_eq(RunCheckpointCodec.safety_error(run), "")
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	assert_true(encoded.ok, encoded.reason)
	assert_eq(encoded.payload.point, "frozen_reward")
	var loaded: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest)
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	var other: RunController = loaded.run
	_same(run, other)
	assert_ne(run.state.rewards.active_offer, other.state.rewards.active_offer)
	var rng: Dictionary = other.state.random_streams.data()
	var snapshot: Dictionary = RunSnapshot.offer_data(other.state.rewards.active_offer)
	var again: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest)
	assert_true(again.ok, again.reason)
	assert_eq(other.state.random_streams.data(), rng)
	assert_eq(RunSnapshot.offer_data(other.state.rewards.active_offer), snapshot)
	var bot: RandomLegalBot = RandomLegalBot.new(1)
	var choice: RunCommand = bot.skill_command(run, run.state.rewards.active_offer.choices[0].skill_id)
	var first: CommandResult = run.execute_command(choice)
	var second: CommandResult = other.execute_command(choice)
	assert_eq(first.accepted, second.accepted)
	assert_true(first.accepted, first.reason)
	var consumed: int = other.state.rewards.consumed_count
	var unchanged: Dictionary = RunSnapshot.capture(other)
	assert_same(other.execute_command(choice), second)
	assert_eq(other.state.rewards.consumed_count, consumed)
	assert_eq(RunSnapshot.capture(other), unchanged)
	_settle(run)
	_settle(other)
	_same(run, other)
	assert_eq(other.recorder.path, "")
	assert_eq(other.recorder.record_appended.get_connections().size(), 0)

func test_shape_unlock_and_empty_recovery_budget_are_reconstructed_without_bonus() -> void:
	var run: RunController = SHAPES.run(true)
	_record(run)
	run.prepare_offer()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	assert_true(encoded.ok, encoded.reason)
	var loaded: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest)
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	var other: RunController = loaded.run
	assert_true(SHAPES.choose(run).accepted)
	assert_true(SHAPES.choose(other).accepted)
	assert_eq(run.advance().kind, other.advance().kind)
	_same(run, other)
	assert_true(other.state.rules.shape_unlocks.recovery_attempted)
	assert_eq(other.state.rewards.acquired.get(&"fixture_unlock_l"), 1)

func test_unsafe_phases_closed_runs_and_unfrozen_rewards_are_rejected() -> void:
	for phase: int in [RunState.Phase.INITIALIZING, RunState.Phase.MOVING, RunState.Phase.TURN_END, RunState.Phase.SPAWNING, RunState.Phase.ERROR, RunState.Phase.FINISHED]:
		var run: RunController = _normal()
		run.state.phase = phase as RunState.Phase
		assert_false(RunCheckpointCodec.encode(run).ok)
	var reward: RunController = _reward()
	reward.state.rewards.active_offer = null
	assert_eq(RunCheckpointCodec.encode(reward).reason, "unfrozen_reward")
	var closed: RunController = _normal()
	closed.retire()
	assert_eq(RunCheckpointCodec.encode(closed).reason, "run_closed")

func test_held_matches_without_blasts_are_not_a_safe_checkpoint() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1)
	for index: int in range(5):
		run.state.rules.place_piece(Vector2i(index, 0), 1)
	run.state.phase = RunState.Phase.INPUT
	run.abilities.resolve(run.state.rules.find_matches(), true)
	assert_true(run.abilities.has_pending_work())
	assert_eq(RunCheckpointCodec.encode(run).reason, "pending_descendants")
	assert_eq(run.abilities.pending_removals().size(), 0)
	assert_eq(run.abilities.pending_followups().size(), 0)
	run.abilities.abandon_held_blasts()
	assert_false(run.abilities.has_pending_work())

func test_snapshot_not_backed_by_complete_prefix_and_partial_tail_are_rejected() -> void:
	var run: RunController = _normal()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	run.state.manual_uses_used[&"core_manual_detonation"] = 1
	assert_eq(RunCheckpointCodec.encode(run).reason, "endpoint_not_recorded")
	var bad: Dictionary = encoded.payload.duplicate(true)
	bad.records.pop_back()
	bad.record_seq = str(bad.records.size())
	assert_eq(RunCheckpointCodec.decode(bad, encoded.manifest).reason, "incomplete_prefix")
	bad = encoded.payload.duplicate(true)
	bad.records[0].rng.streams.erase("spawn_content")
	assert_false(RunCheckpointCodec.decode(bad, encoded.manifest).ok)
	assert_eq(encoded.payload.state.manual_uses_used, {})

func test_corruption_schema_missing_fields_and_integer_encoding_fail_without_touching_live_run() -> void:
	var run: RunController = _reward()
	var before: Dictionary = RunSnapshot.capture(run)
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	var changes: Array[Dictionary] = [
		{"schema": "unknown"}, {"master_seed": 23.0}, {"master_seed": "023"},
		{"record_seq": "999"}, {"point": "rewind"}, {"state_hash": "wrong"},
		{"offer_cache": {"profile_id": "wrong"}}, {"records": [null]},
	]
	for change: Dictionary in changes:
		var bad: Dictionary = encoded.payload.duplicate(true)
		bad.merge(change, true)
		var rejected: Dictionary = RunCheckpointCodec.decode(bad, encoded.manifest)
		assert_false(rejected.ok, str(change))
		assert_false(rejected.has("run"))
		assert_eq(RunSnapshot.capture(run), before)
	for key: String in encoded.payload:
		var bad: Dictionary = encoded.payload.duplicate(true)
		bad.erase(key)
		assert_false(RunCheckpointCodec.decode(bad, encoded.manifest).ok, key)

func test_frozen_endpoint_tampering_cannot_be_hidden_by_rehashing() -> void:
	var run: RunController = _reward()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	for field: String in ["rng", "offer", "spawning", "challenge", "last_command", "reward_repair_used"]:
		var bad: Dictionary = encoded.payload.duplicate(true)
		if bad.state[field] is Dictionary: bad.state[field].clear()
		elif bad.state[field] is bool: bad.state[field] = not bad.state[field]
		else: bad.state[field] = "999"
		bad.state_hash = RunSnapshot.digest(bad.state)
		bad.records.back().state = bad.state.duplicate(true)
		bad.records.back().hash = bad.state_hash
		assert_false(RunCheckpointCodec.decode(bad, encoded.manifest).ok, field)

func test_manifest_and_rebuild_limits_fail_explicitly() -> void:
	var run: RunController = _normal()
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	var wrong: Dictionary = encoded.manifest.duplicate(true)
	wrong.engine_build = "unverified"
	assert_eq(RunCheckpointCodec.decode(encoded.payload, wrong).reason, "manifest_incompatible")
	assert_eq(RunCheckpointCodec.decode(encoded.payload, encoded.manifest, 1).reason, "rebuild_budget_exceeded")
	var bad: Dictionary = encoded.payload.duplicate(true)
	bad.records.resize(RunCheckpointCodec.MAX_RECORDS + 1)
	assert_eq(RunCheckpointCodec.decode(bad, encoded.manifest).reason, "prefix_record_limit")
	bad = encoded.payload.duplicate(true)
	bad.run_id = "x".repeat(RunCheckpointCodec.MAX_PAYLOAD_BYTES)
	assert_eq(RunCheckpointCodec.decode(bad, encoded.manifest).reason, "payload_size_limit")

func test_real_slot_two_generations_new_instance_and_corrupt_primary_fallback() -> void:
	var directory: String = _directory()
	var run: RunController = _normal()
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), policy)
	assert_true(session.save(run).ok)
	var original: Dictionary = RunSnapshot.capture(run)
	var bot: RandomLegalBot = RandomLegalBot.new(1)
	run.execute_command(bot.choose(run))
	_settle(run)
	assert_true(session.save(run).ok)
	var fresh: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), policy)
	var loaded: Dictionary = fresh.load_candidate()
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	_same(run, loaded.run)
	assert_eq(loaded.generation, "2")
	assert_false(loaded.fallback)
	var file: FileAccess = FileAccess.open(directory.path_join("primary.json"), FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var fallback: Dictionary = fresh.load_candidate()
	assert_true(fallback.ok, fallback.reason)
	assert_true(fallback.fallback)
	assert_eq(RunSnapshot.capture(fallback.run), original)
	assert_eq(fallback.generation, "1")

func test_invalidated_run_cannot_reappear_from_primary_or_backup() -> void:
	var directory: String = _directory()
	var run: RunController = _reward()
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var store: CheckpointStore = CheckpointStore.new(directory)
	var session: RunCheckpointSession = RunCheckpointSession.new(store, policy)
	var saved: Dictionary = session.save(run)
	assert_true(saved.ok, saved.reason)
	saved = session.save(run)
	assert_true(saved.ok, saved.reason)
	assert_true(store.invalidate(run.state.run_id, "terminal").ok)
	var fresh: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), policy)
	assert_eq(fresh.load_candidate().reason, "run_invalidated")
	assert_eq(session.save(run).reason, "run_invalidated")

func test_invalid_save_leaves_real_slot_bytes_and_source_unchanged() -> void:
	var directory: String = _directory()
	var run: RunController = _normal()
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), RunCheckpointCodec.manifest(run))
	assert_true(session.save(run).ok)
	var primary: String = FileAccess.get_sha256(directory.path_join("primary.json"))
	run.continuation = &"before_end"
	var before: Dictionary = RunSnapshot.capture(run)
	assert_false(session.save(run).ok)
	assert_eq(FileAccess.get_sha256(directory.path_join("primary.json")), primary)
	assert_eq(RunSnapshot.capture(run), before)
	assert_false(FileAccess.file_exists(directory.path_join("previous.json")))

func test_real_commit_failure_preserves_exact_pair_and_can_retry() -> void:
	var directory: String = _directory()
	var run: RunController = _normal()
	var files: FailingFiles = FailingFiles.new()
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory, files), RunCheckpointCodec.manifest(run))
	assert_true(session.save(run).ok)
	assert_true(session.save(run).ok)
	var pair: Array[String] = [
		FileAccess.get_sha256(directory.path_join("primary.json")),
		FileAccess.get_sha256(directory.path_join("previous.json")),
	]
	files.fail_primary = true
	var before: Dictionary = RunSnapshot.capture(run)
	assert_eq(session.save(run).reason, "primary_commit_failed")
	assert_eq(FileAccess.get_sha256(directory.path_join("primary.json")), pair[0])
	assert_eq(FileAccess.get_sha256(directory.path_join("previous.json")), pair[1])
	assert_eq(RunSnapshot.capture(run), before)
	files.fail_primary = false
	assert_true(session.save(run).ok)
	var loaded: Dictionary = session.load_candidate()
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok: _same(run, loaded.run)

func test_malformed_frozen_targets_are_rejected_before_snapshot_traversal() -> void:
	for case_id: int in range(5):
		var run: RunController = _reward()
		var offer: SkillOffer = run.state.rewards.active_offer
		var id: StringName = offer.choices[0].skill_id
		var nested: CompositeSkillTarget = CompositeSkillTarget.new()
		match case_id:
			0: offer.targets.erase(id)
			1: offer.targets[id] = null
			2: offer.choices[0] = null
			3:
				nested.leaf_targets.append(null)
				offer.targets[id] = nested
			4:
				nested.leaf_targets.append(nested)
				offer.targets[id] = nested
		var rejected: Dictionary = RunCheckpointCodec.encode(run)
		assert_false(rejected.ok, str(case_id))
		assert_true(rejected.reason in ["missing_frozen_target", "invalid_frozen_target"])
		nested.leaf_targets.clear()

func test_frozen_before_end_reopens_from_disk_and_keeps_refill_obligation() -> void:
	var run: RunController = MixedTemplateDemo.new_run("fixture_mixed_nested")
	_record(run)
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, 1, 0)
	command.piece_id = run.state.rules.state.get_piece_id(MixedTemplateDemo.source("fixture_mixed_nested"))
	command.target = MixedTemplateDemo.target("fixture_mixed_nested")
	assert_true(run.execute_command(command).accepted)
	assert_eq(run.advance().kind, &"offer", str(run.state.ledger.total))
	assert_eq(run.continuation, &"before_end")
	var directory: String = _directory()
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), policy)
	var saved: Dictionary = session.save(run)
	assert_true(saved.ok, saved.reason)
	var fresh: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(directory), policy)
	var loaded: Dictionary = fresh.load_candidate()
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	var other: RunController = loaded.run
	_same(run, other)
	assert_gt(other.action_refill_count, 0)
	assert_eq(other.state.spawning.plan_data(), run.state.spawning.plan_data())
	var bot: RandomLegalBot = RandomLegalBot.new(99)
	for index: int in range(12):
		if run.state.rewards.active_offer != null:
			var choice: RunCommand = bot.choose(run)
			assert_eq(run.execute_command(choice).accepted, other.execute_command(choice).accepted)
		else:
			assert_eq(run.advance().kind, other.advance().kind)
		_same(run, other)
		if run.state.phase == RunState.Phase.INPUT and run.continuation == &"idle": break
	assert_eq(other.state.phase, RunState.Phase.INPUT)

func test_manual_use_counts_survive_a_complete_input_checkpoint() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize("fixture_manual_limit")
	_record(run)
	var command: ActivateLineCommand = ActivateLineCommand.new(run.state.run_id, 1, run.state.action_id)
	command.piece_id = run.state.rules.state.get_piece_id(Vector2i(0, 0))
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted, result.reason)
	_settle(run)
	assert_false(run.state.manual_uses_used.is_empty())
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	assert_true(encoded.ok, encoded.reason)
	var loaded: Dictionary = RunCheckpointCodec.decode(encoded.payload, encoded.manifest)
	assert_true(loaded.ok, loaded.reason)
	if loaded.ok: _same(run, loaded.run)

func test_stage_frozen_offer_roundtrips_exact_float_weights_through_real_slot() -> void:
	var run: RunController = _reward()
	var before: Dictionary = RunSnapshot.capture(run)
	var directory: String = _directory()
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var saved: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), policy).save(run)
	assert_true(saved.ok, saved.reason)
	var loaded: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), policy).load_candidate()
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	_same(run, loaded.run)
	assert_eq(RunSnapshot.capture(run), before)
	var next_save: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), policy).save(loaded.run)
	assert_true(next_save.ok, next_save.reason)
	assert_eq(next_save.generation, "2")

func test_bad_storage_packages_fail_without_touching_live_run_or_slot() -> void:
	var run: RunController = _normal()
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var encoded: Dictionary = RunCheckpointCodec.encode(run)
	var before: Dictionary = RunSnapshot.capture(run)
	var packages: Array[Dictionary] = [
		{}, {"schema": "unknown", "run_id": run.state.run_id, "payload_json": "{}"},
		{"schema": RunCheckpointCodec.SCHEMA, "run_id": "other", "payload_json": "{}"},
		{"schema": RunCheckpointCodec.SCHEMA, "run_id": run.state.run_id, "payload_json": "{"},
		{"schema": RunCheckpointCodec.SCHEMA, "run_id": run.state.run_id, "payload_json": "{}"},
	]
	for package: Dictionary in packages:
		var directory: String = _directory()
		var store: CheckpointStore = CheckpointStore.new(directory)
		assert_true(store.begin_run(run.state.run_id).ok)
		assert_true(store.commit(store.stage(package, policy)).ok)
		var original: String = FileAccess.get_sha256(directory.path_join("primary.json"))
		var rejected: Dictionary = RunCheckpointSession.new(CheckpointStore.new(directory), policy).load_candidate()
		assert_false(rejected.ok)
		assert_false(rejected.has("run"))
		assert_eq(FileAccess.get_sha256(directory.path_join("primary.json")), original)
		assert_eq(RunSnapshot.capture(run), before)
	assert_true(encoded.ok)
