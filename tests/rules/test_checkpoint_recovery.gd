extends GutTest

## Rule-level corruption falls back only after the primary passed the current container policy.
var _directories: Array[String] = []

func after_each() -> void:
	for directory: String in _directories:
		for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
		DirAccess.remove_absolute(directory)
	_directories.clear()

func _pair() -> Dictionary:
	var directory: String = "user://checkpoint-recovery-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.append(directory)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_recovery_test", false)
	var store: CheckpointStore = CheckpointStore.new(directory)
	var policy: Dictionary = RunCheckpointCodec.manifest(run)
	var session: RunCheckpointSession = RunCheckpointSession.new(store, policy)
	assert_true(session.save(run).ok)
	var older: Dictionary = RunSnapshot.capture(run)
	var bot: GreedyBot = GreedyBot.new(23)
	assert_true(run.execute_command(bot.choose(run)).accepted)
	for index: int in range(30):
		if RunCheckpointCodec.safety_error(run).is_empty(): break
		run.advance()
	assert_true(session.save(run).ok)
	return {"directory": directory, "run": run, "store": store, "session": session, "policy": policy, "older": older}

func _write(path: String, value: Dictionary) -> void:
	var content: Dictionary = value.duplicate(true)
	content.erase("digest")
	value["digest"] = JSON.stringify(content, "", true).sha256_text()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", true))
	file.close()

func _corrupt(directory: String, schema: bool = false) -> void:
	var path: String = directory.path_join("primary.json")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var payload: Dictionary = JSON.parse_string(record.payload.payload_json)
	if schema: payload.schema = "future-checkpoint-v99"
	else: payload.state_hash = "broken-endpoint-hash"
	record.payload.payload_json = JSON.stringify(payload, "", true, true)
	_write(path, record)

func test_rule_bad_primary_recovers_previous_without_rewriting_and_next_save_keeps_verified_backup() -> void:
	var pair: Dictionary = _pair()
	_corrupt(pair.directory)
	var bad_hash: String = FileAccess.get_sha256(pair.directory.path_join("primary.json"))
	var good_hash: String = FileAccess.get_sha256(pair.directory.path_join("previous.json"))
	var restored: Dictionary = pair.session.load_candidate()
	assert_true(restored.ok, restored.reason)
	if not restored.ok: return
	assert_true(restored.fallback)
	assert_eq(RunSnapshot.capture(restored.run), pair.older)
	assert_eq(restored.primary_rejection, "endpoint_hash_mismatch")
	assert_eq(FileAccess.get_sha256(pair.directory.path_join("primary.json")), bad_hash)
	assert_eq(FileAccess.get_sha256(pair.directory.path_join("previous.json")), good_hash)
	assert_true(pair.session.save(restored.run).ok)
	assert_eq(FileAccess.get_sha256(pair.directory.path_join("previous.json")), good_hash, "do not rotate rejected primary over the verified backup")
	assert_eq(FileAccess.get_sha256(pair.directory.path_join("primary.json.corrupt-" + bad_hash + ".json")), bad_hash)
	assert_true(RunCheckpointSession.new(CheckpointStore.new(pair.directory), pair.policy).load_candidate().ok)

func test_both_rule_bad_fail_and_keep_originals() -> void:
	var pair: Dictionary = _pair()
	_corrupt(pair.directory)
	var source: String = pair.directory.path_join("primary.json")
	assert_eq(DirAccess.copy_absolute(source, pair.directory.path_join("previous.json")), OK)
	var before: String = FileAccess.get_sha256(source)
	assert_false(pair.session.load_candidate().ok)
	assert_eq(FileAccess.get_sha256(source), before)
	assert_eq(FileAccess.get_sha256(pair.directory.path_join("previous.json")), before)

func test_unknown_payload_schema_is_not_silently_rolled_back() -> void:
	var pair: Dictionary = _pair()
	_corrupt(pair.directory, true)
	var result: Dictionary = pair.session.load_candidate()
	assert_false(result.ok)
	assert_eq(result.reason, "schema_unsupported")

func test_manifest_mismatch_and_budget_rejection_do_not_select_previous() -> void:
	var pair: Dictionary = _pair()
	var policy: Dictionary = pair.policy.duplicate(true)
	policy.rules_version = "unknown-rules"
	assert_eq(RunCheckpointSession.new(pair.store, policy).load_candidate().reason, "manifest_incompatible")
	pair.session.rebuild_budget_usec = 0
	assert_eq(pair.session.load_candidate().reason, "rebuild_budget_exceeded")

func test_terminal_invalidation_overrides_rule_bad_primary_and_valid_previous() -> void:
	var pair: Dictionary = _pair()
	_corrupt(pair.directory)
	assert_true(pair.store.invalidate(pair.run.state.run_id, "terminal").ok)
	assert_eq(RunCheckpointSession.new(CheckpointStore.new(pair.directory), pair.policy).load_candidate().reason, "run_invalidated")

func test_known_initial_state_and_missing_stream_corruption_recover_previous() -> void:
	for kind: String in ["rng", "initial"]:
		var pair: Dictionary = _pair()
		var path: String = pair.directory.path_join("primary.json")
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var payload: Dictionary = JSON.parse_string(record.payload.payload_json)
		payload.records[0][kind] = {}
		record.payload.payload_json = JSON.stringify(payload, "", true, true)
		_write(path, record)
		var restored: Dictionary = pair.session.load_candidate()
		assert_true(restored.ok, restored.reason)
		if restored.ok:
			assert_true(restored.fallback)
			assert_eq(RunSnapshot.capture(restored.run), pair.older)

func test_unknown_header_rng_protocol_does_not_fall_back() -> void:
	var pair: Dictionary = _pair()
	var path: String = pair.directory.path_join("primary.json")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var payload: Dictionary = JSON.parse_string(record.payload.payload_json)
	payload.records[0].rng_scheme_version = "future-rng-v99"
	record.payload.payload_json = JSON.stringify(payload, "", true, true)
	_write(path, record)
	assert_eq(pair.session.load_candidate().reason, "rebuild_failed:unsupported_rng_scheme")
