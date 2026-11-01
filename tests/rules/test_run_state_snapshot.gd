extends GutTest

## Current-state continuation checks. No prefix reader or replay is used by the candidate.
const SNAPSHOT: Script = preload("res://services/run_checkpoint/run_state_snapshot.gd")
const RESTORE: Script = preload("res://services/run_checkpoint/snapshot_run_restore.gd")
var _directories: Array[String] = []

class RejectingFiles extends CheckpointFiles:
	func write_text(_path: String, _text: String) -> Error:
		return ERR_CANT_CREATE

class HistoryCountingLedger extends ScoreLedger:
	var history_reads: int = 0
	func get_entries() -> Array[ScoreEntry]:
		history_reads += 1
		return super.get_entries()

func test_snapshot_save_does_not_even_read_scoring_history() -> void:
	var run: RunController = _run()
	var ledger: HistoryCountingLedger = HistoryCountingLedger.new()
	run.state.ledger = ledger
	assert_true((await SNAPSHOT.save(CheckpointStore.new(_directory()), run)).ok)
	assert_eq(ledger.history_reads, 0)
	RunSnapshot.capture(run)
	assert_eq(ledger.history_reads, 1, "legacy full capture still includes history")

func test_transport_rejects_a_scalar_float_tag_instead_of_a_snapshot_object() -> void:
	var bytes: PackedByteArray = '{"$checkpoint_float64":"000000000000f03f"}'.to_utf8_buffer()
	assert_false(SNAPSHOT.deserialize(bytes).ok)

func after_each() -> void:
	for directory: String in _directories:
		if not DirAccess.dir_exists_absolute(directory): continue
		for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
		DirAccess.remove_absolute(directory)
	_directories.clear()

func _run(seed_value: int = 23) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "snapshot_test", false, Engine.get_version_info().hash)
	return run

func _directory() -> String:
	var directory: String = "user://snapshot-input-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.append(directory)
	return directory

func _reach_input(run: RunController, bot: GreedyBot) -> bool:
	for index: int in range(100):
		if run.state.is_game_over or not run.state.rule_error.is_empty(): return false
		if run.state.phase == RunState.Phase.INPUT: return true
		if run.state.rewards.active_offer != null:
			var chosen: RunCommand = bot.choose(run)
			if chosen == null or not run.execute_command(chosen).accepted: return false
		else: run.advance()
	return false

func _same_input(a: RunController, b: RunController, bot: GreedyBot) -> bool:
	for index: int in range(100):
		if a.state.is_game_over or b.state.is_game_over: return false
		assert_eq(RESTORE.project(a), RESTORE.project(b))
		if a.state.phase == RunState.Phase.INPUT: return b.state.phase == RunState.Phase.INPUT
		if a.state.rewards.active_offer != null:
			var command: RunCommand = bot.choose(a)
			if command == null: return false
			var copied: RunCommand = CommandCodec.decode(CommandCodec.encode(command))
			assert_eq(a.execute_command(command).accepted, b.execute_command(copied).accepted)
		else:
			a.advance()
			b.advance()
	return false

func test_initial_max_seed_restores_without_initialize_and_owns_all_mutable_state() -> void:
	var run: RunController = _run(9223372036854775807)
	var old_event: AbilityEvent = run.state.ability_events.removal(run.state.rules.state.get_snapshot()[0], &"test_scope", 0, 0, run.state.run_id)
	run.state.ability_events.dispatch([old_event], [])
	var before: Dictionary = RunSnapshot.capture(run)
	var template_weights: Array[int] = RunController.SPAWN_CONFIG.color_weights.duplicate()
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	assert_true(frozen.ok, frozen.reason)
	var encoded: Dictionary = SNAPSHOT.serialize(frozen.payload)
	assert_true(encoded.ok, encoded.reason)
	var transported: Dictionary = SNAPSHOT.deserialize(encoded.bytes)
	assert_true(transported.ok, transported.reason)
	var restored: Dictionary = SNAPSHOT.decode(transported.data, SNAPSHOT.manifest(run))
	assert_true(restored.ok, restored.reason)
	if not restored.ok: return
	var candidate: RunController = restored.run
	assert_eq(RESTORE.project(candidate), RESTORE.project(run))
	assert_null(candidate.recorder, "no historical recorder is required to reconstruct the candidate")
	assert_ne(candidate.state.random_streams, run.state.random_streams)
	var event_state: Dictionary = candidate.state.ability_events.data()
	assert_true(candidate.state.ability_events.dispatch([old_event], []).is_empty())
	assert_eq(candidate.state.ability_events.data(), event_state, "old event scope is rejected, without retaining past dispatch IDs")
	var first: PieceState = candidate.state.rules.state.get_snapshot()[0]
	candidate.state.rules.set_piece_color(first.piece_id, (first.match_color + 1) % 5)
	candidate.state.spawning.color_weights[0] += 5
	candidate.state.random.randi()
	assert_eq(RunSnapshot.capture(run), before)
	assert_eq(RunController.SPAWN_CONFIG.color_weights, template_weights)

func test_real_file_restore_after_normal_play_keeps_multiple_next_commands_equal_without_history() -> void:
	var run: RunController = _run()
	var bot: GreedyBot = GreedyBot.new(100023)
	for index: int in range(20):
		assert_true(_reach_input(run, bot))
		var command: RunCommand = bot.choose(run)
		assert_not_null(command)
		if command == null: return
		assert_true(run.execute_command(command).accepted)
	assert_true(_reach_input(run, bot))
	var before: Dictionary = RESTORE.project(run)
	var frozen: Dictionary = SNAPSHOT.freeze(run)
	assert_true(frozen.ok, frozen.reason)
	assert_false(frozen.payload.has("records"))
	assert_false(frozen.payload.state.has("ledger"))
	assert_gt(frozen.payload.state.skills.size(), 0, "normal play must exercise nonempty skill instances")
	var duplicate: Dictionary = frozen.payload.duplicate(true)
	duplicate.state.skills.append(duplicate.state.skills[0].duplicate(true))
	duplicate.state_hash = RunSnapshot.digest(duplicate.state)
	assert_false(SNAPSHOT.decode(duplicate, SNAPSHOT.manifest(run)).ok)
	var encoded: Dictionary = SNAPSHOT.serialize(frozen.payload)
	assert_true(encoded.ok, encoded.reason)
	var records: Array[Dictionary] = run.recorder.records
	run.recorder.records = []
	assert_eq(SNAPSHOT.serialize(SNAPSHOT.freeze(run).payload).bytes, encoded.bytes, "save bytes are independent of all past recorder rows")
	run.recorder.records = records
	var directory: String = _directory()
	var saved: Dictionary = await SNAPSHOT.save(CheckpointStore.new(directory), run)
	assert_true(saved.ok, saved.reason)
	if not saved.ok: return
	assert_lt(saved.snapshot_bytes, 100000, "measured sample bound, not a universal product budget")
	var loaded: Dictionary = SNAPSHOT.load(CheckpointStore.new(directory), SNAPSHOT.manifest(run))
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	var candidate: RunController = loaded.run
	assert_eq(RESTORE.project(candidate), before)
	var commands: int = 0
	for index: int in range(8):
		assert_true(_same_input(run, candidate, bot))
		assert_eq(RESTORE.project(candidate), RESTORE.project(run))
		var command: RunCommand = bot.choose(run)
		if command == null: break
		assert_eq(candidate.execute_command(CommandCodec.decode(CommandCodec.encode(command))).accepted, run.execute_command(command).accepted)
		assert_eq(RESTORE.project(candidate), RESTORE.project(run))
		commands += 1
	assert_eq(commands, 8)

func test_long_normal_input_snapshot_has_no_prefix_cost_and_continues_identical_commands() -> void:
	var run: RunController = _run()
	var bot: GreedyBot = GreedyBot.new(100023)
	for index: int in range(300):
		if not _reach_input(run, bot) or run.state.valid_moves >= 45: break
		var command: RunCommand = bot.choose(run)
		if command == null: break
		run.execute_command(command)
	assert_true(_reach_input(run, bot))
	assert_eq(run.state.valid_moves, 45)
	var history_count: int = run.recorder.records.size()
	var before: Dictionary = RESTORE.project(run)
	var directory: String = _directory()
	var started: int = Time.get_ticks_usec()
	var saved: Dictionary = await SNAPSHOT.save(CheckpointStore.new(directory), run)
	var save_usec: int = Time.get_ticks_usec() - started
	assert_true(saved.ok, saved.reason)
	if not saved.ok: return
	started = Time.get_ticks_usec()
	var loaded: Dictionary = SNAPSHOT.load(CheckpointStore.new(directory), SNAPSHOT.manifest(run))
	var load_usec: int = Time.get_ticks_usec() - started
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	assert_eq(RESTORE.project(loaded.run), before)
	print("SNAPSHOT_INPUT_REPORT " + JSON.stringify({"platform": OS.get_name(), "moves": run.state.valid_moves, "source_records_not_saved": history_count, "snapshot_bytes": saved.snapshot_bytes, "save_usec": save_usec, "load_usec": load_usec, "state_hash": RunSnapshot.digest(before), "scope": "native kernel/file roundtrip, not product UI or Web acceptance"}))
	var commands: int = 0
	for index: int in range(5):
		assert_true(_same_input(run, loaded.run, bot))
		var command: RunCommand = bot.choose(run)
		if command == null: break
		assert_eq(loaded.run.execute_command(CommandCodec.decode(CommandCodec.encode(command))).accepted, run.execute_command(command).accepted)
		assert_eq(RESTORE.project(loaded.run), RESTORE.project(run))
		commands += 1
	assert_eq(commands, 5)

func test_rehashed_bad_state_and_missing_stream_never_repair_into_a_candidate() -> void:
	var run: RunController = _run()
	var payload: Dictionary = SNAPSHOT.freeze(run).payload
	var before: Dictionary = RunSnapshot.capture(run)
	var mutations: Array[Callable] = [
		func(s: Dictionary) -> void: s.pieces.append(s.pieces[0].duplicate(true)),
		func(s: Dictionary) -> void: s.pieces[0].coordinate = ["-1", "0"],
		func(s: Dictionary) -> void: s.next_piece_id = "1",
		func(s: Dictionary) -> void: s.rng.streams.erase("effect_execution"),
		func(s: Dictionary) -> void: s.spawning.color_weights = ["0", "0", "0", "0", "0"],
		func(s: Dictionary) -> void: s.skills = [{"skill_id": "unknown"}],
		func(s: Dictionary) -> void: s.phase = "3",
		func(s: Dictionary) -> void: s.unexpected = true,
	]
	for mutate: Callable in mutations:
		var bad: Dictionary = payload.duplicate(true)
		mutate.call(bad.state)
		bad.state_hash = RunSnapshot.digest(bad.state)
		assert_false(SNAPSHOT.decode(bad, SNAPSHOT.manifest(run)).ok)
	for key: String in payload.state:
		var bad: Dictionary = payload.duplicate(true)
		bad.state[key] = null
		bad.state_hash = RunSnapshot.digest(bad.state)
		assert_false(SNAPSHOT.decode(bad, SNAPSHOT.manifest(run)).ok, "null state field: " + key)
	for section: String in ["spawning", "demolition", "dye", "challenge", "ability_events", "shape_unlocks", "line_clear"]:
		for key: String in payload.state[section]:
			var bad: Dictionary = payload.duplicate(true)
			bad.state[section][key] = null
			bad.state_hash = RunSnapshot.digest(bad.state)
			assert_false(SNAPSHOT.decode(bad, SNAPSHOT.manifest(run)).ok, "null nested field: " + section + "." + key)
	assert_eq(RunSnapshot.capture(run), before)

func test_unsupported_phase_and_legacy_slot_are_preserved() -> void:
	var run: RunController = _run()
	var directory: String = _directory()
	var legacy: CheckpointStore = CheckpointStore.new(directory)
	assert_true(RunCheckpointSession.new(legacy, RunCheckpointCodec.manifest(run)).save(run).ok)
	var old: String = FileAccess.get_file_as_string(directory.path_join("primary.json"))
	var saved: Dictionary = await SNAPSHOT.save(legacy, run)
	assert_false(saved.ok)
	assert_eq(saved.reason, "snapshot_slot_requires_migration")
	assert_eq(FileAccess.get_file_as_string(directory.path_join("primary.json")), old)

	run.state.phase = RunState.Phase.SPAWNING
	assert_eq((await SNAPSHOT.save(legacy, run)).reason, "snapshot_input_classic_only")
	assert_eq(FileAccess.get_file_as_string(directory.path_join("primary.json")), old)

func test_snapshot_payload_fallback_keeps_valid_previous_and_preserves_bad_original() -> void:
	var run: RunController = _run()
	var bot: GreedyBot = GreedyBot.new(100023)
	var directory: String = _directory()
	var store: CheckpointStore = CheckpointStore.new(directory)
	assert_true((await SNAPSHOT.save(store, run)).ok)
	var first: Dictionary = RESTORE.project(run)
	assert_true(run.execute_command(bot.choose(run)).accepted)
	assert_true(_reach_input(run, bot))
	assert_true((await SNAPSHOT.save(store, run)).ok)
	var primary: String = directory.path_join("primary.json")
	var bad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(primary))
	bad.payload.snapshot_json = "{invalid snapshot"
	bad.erase("digest")
	bad = CheckpointStore._seal(bad)
	var file: FileAccess = FileAccess.open(primary, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad, "", true))
	file.close()
	var original: String = FileAccess.get_file_as_string(primary)
	var reader: CheckpointStore = CheckpointStore.new(directory)
	var loaded: Dictionary = SNAPSHOT.load(reader, SNAPSHOT.manifest(run))
	assert_true(loaded.ok, loaded.reason)
	if not loaded.ok: return
	assert_true(loaded.fallback)
	assert_eq(RESTORE.project(loaded.run), first)
	assert_eq(FileAccess.get_file_as_string(primary), original)
	assert_true((await SNAPSHOT.save(reader, loaded.run)).ok)
	assert_true(FileAccess.file_exists(directory.path_join("primary.json.corrupt-" + original.sha256_text() + ".json")))
	assert_eq(SNAPSHOT.load(CheckpointStore.new(directory), SNAPSHOT.manifest(run)).run.state.ledger.total, loaded.run.state.ledger.total)

func test_failed_snapshot_write_keeps_pair_and_invalidation_still_blocks_load() -> void:
	var run: RunController = _run()
	var directory: String = _directory()
	assert_true((await SNAPSHOT.save(CheckpointStore.new(directory), run)).ok)
	var primary: String = FileAccess.get_file_as_string(directory.path_join("primary.json"))
	var before: Dictionary = RESTORE.project(run)
	var failed: Dictionary = await SNAPSHOT.save(CheckpointStore.new(directory, RejectingFiles.new()), run)
	assert_false(failed.ok)
	assert_eq(FileAccess.get_file_as_string(directory.path_join("primary.json")), primary)
	assert_eq(RESTORE.project(run), before)
	assert_true(CheckpointStore.new(directory).invalidate(run.state.run_id, "terminal").ok)
	assert_eq(SNAPSHOT.load(CheckpointStore.new(directory), SNAPSHOT.manifest(run)).reason, "run_invalidated")
