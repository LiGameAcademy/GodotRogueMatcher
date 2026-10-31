extends GutTest

## Faults the actual synchronous adapter contract, including failures after a write took effect.
class MemoryFiles extends CheckpointFiles:
	var data: Dictionary[String, String] = {}
	var failures: Dictionary[String, int] = {}
	var crash_after: String = ""
	var offline: bool = false
	var on_write: Callable
	var writes: int = 0
	var corrupt_next_write: bool = false

	func exists(path: String) -> bool:
		return data.has(path)

	func read_text(path: String) -> Dictionary:
		if not exists(path): return {"ok": false, "reason": "missing", "text": ""}
		if _fails("read:" + path.get_file()): return {"ok": false, "reason": "read_failed", "text": ""}
		return {"ok": true, "reason": "", "text": data[path]}

	func write_text(path: String, text: String) -> Error:
		if _fails("write:" + path.get_file()): return ERR_CANT_CREATE
		if on_write.is_valid():
			var callback: Callable = on_write
			on_write = Callable()
			callback.call()
		writes += 1
		data[path] = text
		if corrupt_next_write:
			data[path] = text.replace("original", "tampered")
			corrupt_next_write = false
		return OK

	func replace(source: String, destination: String) -> Error:
		var key: String = "replace:" + source.get_file()
		if _fails(key) or not data.has(source): return ERR_CANT_CREATE
		data[destination] = data[source]
		data.erase(source)
		if crash_after == key:
			offline = true
			return ERR_UNAVAILABLE
		return OK

	func fingerprint(path: String) -> String:
		return data[path].sha256_text() if data.has(path) and not offline else ""

	func copy_verified(source: String, destination: String) -> Error:
		if _fails("copy:" + destination.get_file()) or not data.has(source): return ERR_CANT_CREATE
		data[destination] = data[source]
		return OK

	func remove(path: String) -> Error:
		if _fails("remove:" + path.get_file()): return ERR_CANT_CREATE
		data.erase(path)
		return OK

	func _fails(key: String) -> bool:
		if offline: return true
		if failures.get(key, 0) <= 0: return false
		failures[key] -= 1
		return true

## Real files, with a bounded failure immediately before/after one rename.
class FaultDiskFiles extends CheckpointFiles:
	var fail_source: String = ""
	var interrupt_primary: bool = false
	var offline: bool = false

	func replace(source: String, destination: String) -> Error:
		if source.get_file() == fail_source:
			fail_source = ""
			return ERR_CANT_CREATE
		var error: Error = super.replace(source, destination)
		if error == OK and interrupt_primary and source.get_file() == "checkpoint.tmp":
			offline = true
			return ERR_UNAVAILABLE
		return error

	func read_text(path: String) -> Dictionary:
		if offline: return {"ok": false, "reason": "read_failed", "text": ""}
		return super.read_text(path)

const DIRECTORY: String = "memory://slot"
const MANIFEST: Dictionary = {"rules": "fixture-r1", "content": "fixture-c1", "config": "fixture-a"}
var files: MemoryFiles
var store: CheckpointStore

func test_sliced_commit_blocks_all_competing_operations_between_phases() -> void:
	_seed_pair()
	var ticket: int = store.stage(_payload("sliced"), MANIFEST)
	var yields: Array[int] = [0]
	var between: Callable = func() -> void:
		yields[0] += 1
		assert_eq(store.load_latest(MANIFEST).reason, "busy")
		assert_eq(store.begin_run("run-b").reason, "busy")
		assert_eq(store.invalidate("run-a", "abandoned").reason, "busy")
		assert_eq(store.commit(ticket).reason, "busy")
		assert_eq(store.stage(_payload("intruder"), MANIFEST), 0)
		assert_eq((await store.sync()).reason, "busy")
		await get_tree().process_frame
	var committed: Dictionary = await store.commit_sliced(ticket, between)
	assert_true(committed.ok, committed.reason)
	assert_gt(yields[0], 8, "container and backup validation expose additional protected frame boundaries")
	var completed_yields: int = yields[0]
	assert_eq(store.load_latest(MANIFEST).record.payload, _payload("sliced"))
	assert_true(store.commit(ticket).ok)
	assert_true((await store.commit_sliced(ticket, between)).duplicate)
	assert_eq(yields[0], completed_yields, "an acknowledged duplicate never replays phases")

func test_sliced_faults_preserve_exact_pair_and_release_ownership_for_retry() -> void:
	var faults: Array[String] = ["write:checkpoint.tmp", "read:checkpoint.tmp", "copy:primary.rollback", "copy:previous.rollback", "write:transaction.tmp", "read:transaction.tmp", "replace:transaction.tmp", "write:previous.tmp", "read:previous.tmp", "replace:previous.tmp", "replace:checkpoint.tmp", "remove:transaction.json", "read:primary.json"]
	for fault: String in faults:
		before_each()
		_seed_pair()
		var primary: String = files.data[_path("primary.json")]
		var previous: String = files.data[_path("previous.json")]
		files.failures[fault] = 1
		var ticket: int = store.stage(_payload("failed"), MANIFEST)
		var failed: Dictionary = await store.commit_sliced(ticket, _yield_frame)
		assert_false(failed.ok, fault)
		assert_eq(files.data[_path("primary.json")], primary, fault)
		assert_eq(files.data[_path("previous.json")], previous, fault)
		assert_true((await store.commit_sliced(ticket, _yield_frame)).ok, "retry: " + fault)
		assert_eq(store.load_latest(MANIFEST).record.payload, _payload("failed"), fault)

func _yield_frame() -> void:
	await get_tree().process_frame

func before_each() -> void:
	files = MemoryFiles.new()
	store = CheckpointStore.new(DIRECTORY, files)
	assert_true(store.begin_run("run-a").ok)

func test_primary_previous_frozen_values_and_64_bit_string_round_trip() -> void:
	var payload: Dictionary = _payload("first")
	var manifest: Dictionary = MANIFEST.duplicate(true)
	var ticket: int = store.stage(payload, manifest)
	payload.nested[0].value = "changed"
	manifest.rules = "changed"
	assert_true(store.commit(ticket).ok)
	var restored: Dictionary = store.load_latest(MANIFEST)
	assert_true(restored.ok)
	assert_false(restored.fallback)
	assert_eq(restored.record.payload, _payload("first"))
	restored.record.payload.nested[0].value = "mutated_return_value"
	assert_eq(store.load_latest(MANIFEST).record.payload, _payload("first"))
	_save("second")
	var previous: Dictionary = JSON.parse_string(files.data[_path("previous.json")]) as Dictionary
	assert_eq(previous.payload, _payload("first"))
	assert_eq(store.load_latest(MANIFEST).record.payload, _payload("second"))

func test_stale_tickets_duplicate_commit_and_reentry() -> void:
	var old: int = store.stage(_payload("old"), MANIFEST)
	var current: int = store.stage(_payload("new"), MANIFEST)
	assert_eq(store.commit(old).reason, "stale_ticket")
	assert_true(files.data.is_empty())
	var reentry: Array[Variant] = []
	files.on_write = func() -> void:
		reentry.append(store.stage(_payload("reentry"), MANIFEST))
		reentry.append(store.begin_run("run-b").reason)
		reentry.append(store.commit(current).reason)
	assert_true(store.commit(current).ok)
	assert_eq(reentry, [0, "busy", "busy"])
	var writes: int = files.writes
	assert_true(store.commit(current).duplicate)
	assert_eq(files.writes, writes)
	store.stage(_payload("next"), MANIFEST)
	assert_eq(store.commit(current).reason, "stale_ticket")

func test_invalid_values_and_manifests_never_advance_or_write() -> void:
	for payload: Dictionary in [{"number": 42}, {"object": Resource.new()}, {"coordinate": Vector2i.ZERO}, {"number": NAN}, {1: "not_string_key"}]:
		assert_eq(store.stage(payload, MANIFEST), 0)
	var cycle: Dictionary = {}
	cycle["self"] = cycle
	assert_eq(store.stage(cycle, MANIFEST), 0)
	cycle.clear()
	assert_eq(store.stage(_payload("x"), {}), 0)
	assert_eq(store.stage(_payload("x"), {"rules": 1}), 0)
	assert_true(files.data.is_empty())
	assert_eq(store.stage(_payload("valid"), MANIFEST), 1)
	assert_false(CheckpointStore.new(DIRECTORY, files).begin_run("../escape").ok)

func test_corrupt_primary_falls_back_and_repair_preserves_original() -> void:
	_seed_pair()
	files.data[_path("primary.json")] = "{broken"
	var reopened: CheckpointStore = CheckpointStore.new(DIRECTORY, files)
	var loaded: Dictionary = reopened.load_latest(MANIFEST)
	assert_true(loaded.ok)
	assert_true(loaded.fallback)
	assert_eq(loaded.record.payload, _payload("one"))
	assert_true(reopened.begin_run("run-a").ok)
	assert_true(reopened.commit(reopened.stage(_payload("repair"), MANIFEST)).ok)
	assert_eq(files.data[_path("primary.json.corrupt-" + "{broken".sha256_text() + ".json")], "{broken")
	assert_eq(reopened.load_latest(MANIFEST).record.payload, _payload("repair"))

func test_unknown_schema_incompatible_manifest_and_both_corrupt_refuse() -> void:
	_seed_pair()
	var original: String = files.data[_path("primary.json")]
	files.data[_path("primary.json")] = original.replace(CheckpointStore.FORMAT, "future-format")
	assert_eq(store.load_latest(MANIFEST).reason, "schema_unsupported")
	assert_false(store.begin_run("run-a").ok)
	files.data[_path("primary.json")] = original
	assert_eq(store.load_latest({"rules": "other"}).reason, "manifest_incompatible")
	files.data[_path("primary.json")] = "{}"
	assert_true(store.load_latest(MANIFEST).fallback)
	files.data[_path("previous.json")] = "{bad"
	var before: Dictionary = files.data.duplicate()
	assert_false(store.load_latest(MANIFEST).ok)
	assert_false(store.begin_run("run-a").ok)
	assert_eq(files.data, before)

func test_write_read_copy_replace_and_finish_failures_preserve_exact_old_pair() -> void:
	var faults: Array[String] = ["write:checkpoint.tmp", "read:checkpoint.tmp", "copy:primary.rollback", "copy:previous.rollback", "write:transaction.tmp", "read:transaction.tmp", "replace:transaction.tmp", "write:previous.tmp", "read:previous.tmp", "replace:previous.tmp", "replace:checkpoint.tmp", "remove:transaction.json", "read:primary.json"]
	for fault: String in faults:
		before_each()
		_seed_pair()
		var primary: String = files.data[_path("primary.json")]
		var previous: String = files.data[_path("previous.json")]
		files.failures[fault] = 1
		var ticket: int = store.stage(_payload("failed"), MANIFEST)
		assert_false(store.commit(ticket).ok, fault)
		assert_eq(files.data[_path("primary.json")], primary, fault)
		assert_eq(files.data[_path("previous.json")], previous, fault)
		assert_true(store.commit(ticket).ok, "retry: " + fault)
		assert_eq(store.load_latest(MANIFEST).record.payload, _payload("failed"), fault)

func test_interrupted_commit_recovers_old_pair_before_loading() -> void:
	_seed_pair()
	var primary: String = files.data[_path("primary.json")]
	var previous: String = files.data[_path("previous.json")]
	files.crash_after = "replace:checkpoint.tmp"
	var result: Dictionary = store.commit(store.stage(_payload("unacknowledged"), MANIFEST))
	assert_false(result.ok)
	assert_true(String(result.reason).contains("rollback_pending"))
	assert_true(files.exists(_path("transaction.json")))
	files.offline = false
	files.crash_after = ""
	var reopened: CheckpointStore = CheckpointStore.new(DIRECTORY, files)
	var restored: Dictionary = reopened.load_latest(MANIFEST)
	assert_true(restored.ok)
	assert_true(restored.recovered_write)
	assert_eq(files.data[_path("primary.json")], primary)
	assert_eq(files.data[_path("previous.json")], previous)
	assert_false(files.exists(_path("transaction.json")))

func test_corrupt_journal_and_rollback_copy_fail_closed() -> void:
	for corrupt_name: String in ["transaction.json", "primary.rollback"]:
		before_each()
		_seed_pair()
		files.crash_after = "replace:checkpoint.tmp"
		assert_false(store.commit(store.stage(_payload("unfinished"), MANIFEST)).ok)
		files.offline = false
		files.crash_after = ""
		files.data[_path(corrupt_name)] = "corrupt"
		var before: Dictionary = files.data.duplicate()
		assert_false(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).ok)
		assert_eq(files.data, before)

func test_reopen_identity_and_invalidation_override_both_generations() -> void:
	_seed_pair()
	assert_eq(CheckpointStore.new(DIRECTORY, files).begin_run("run-b").reason, "previous_run_requires_invalidation")
	var old: int = store.stage(_payload("old_callback"), MANIFEST)
	assert_true(store.invalidate("run-a", "restart").ok)
	assert_false(store.commit(old).ok)
	assert_false(store.begin_run("run-a").ok)
	assert_true(store.begin_run("run-b").ok)
	_save("new_run")
	files.data[_path("primary.json")] = "corrupt"
	assert_eq(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).reason, "run_invalidated")

func test_invalidation_failure_never_claims_success_or_reopens_old_tickets() -> void:
	var marker_temp: String = "invalid-" + "run-a".sha256_text() + ".json.tmp"
	for fault: String in ["write:" + marker_temp, "read:" + marker_temp, "replace:" + marker_temp]:
		before_each()
		_seed_pair()
		var old: int = store.stage(_payload("old_callback"), MANIFEST)
		files.failures[fault] = 1
		assert_false(store.invalidate("run-a", "terminal").ok, fault)
		assert_false(store.commit(old).ok, fault)
		assert_eq(store.load_latest(MANIFEST).reason, "invalidation_pending", fault)
		assert_false(store.begin_run("run-a").ok, fault)
		assert_false(store.begin_run("run-b").ok, fault)
		assert_true(store.invalidate("run-a", "terminal").ok, fault)
		assert_true(store.begin_run("run-b").ok, fault)

func test_terminal_and_corrupt_invalidation_markers_block_backup_revival() -> void:
	_seed_pair()
	assert_true(store.invalidate("run-a", "terminal").ok)
	files.data[_path("primary.json")] = "corrupt"
	assert_eq(store.load_latest(MANIFEST).reason, "run_invalidated")
	files.data[_path("invalid-" + "run-a".sha256_text() + ".json")] = "bad-marker"
	assert_eq(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).reason, "invalidation_unreadable")

func test_late_invalidation_error_may_have_committed_and_is_not_a_rollback() -> void:
	_seed_pair()
	files.crash_after = "replace:invalid-" + "run-a".sha256_text() + ".json.tmp"
	assert_false(store.invalidate("run-a", "terminal").ok)
	files.offline = false
	files.crash_after = ""
	assert_eq(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).reason, "run_invalidated")
	assert_true(store.invalidate("run-a", "terminal").duplicate)

func test_completed_old_ticket_is_rejected_after_external_invalidation() -> void:
	var ticket: int = store.stage(_payload("old"), MANIFEST)
	assert_true(store.commit(ticket).ok)
	assert_true(CheckpointStore.new(DIRECTORY, files).invalidate("run-a", "abandoned").ok)
	assert_eq(store.commit(ticket).reason, "run_invalidated")

func test_stale_owner_cannot_overwrite_a_newer_disk_generation() -> void:
	_seed_pair()
	var old: int = store.stage(_payload("stale"), MANIFEST)
	var newer: CheckpointStore = CheckpointStore.new(DIRECTORY, files)
	assert_true(newer.begin_run("run-a").ok)
	assert_true(newer.commit(newer.stage(_payload("newer"), MANIFEST)).ok)
	assert_eq(store.commit(old).reason, "stale_disk_generation")
	assert_eq(newer.load_latest(MANIFEST).record.payload, _payload("newer"))

func test_valid_json_checksum_damage_is_rejected_on_readback_and_load() -> void:
	_seed_pair()
	var primary: String = files.data[_path("primary.json")]
	var previous: String = files.data[_path("previous.json")]
	files.corrupt_next_write = true
	var ticket: int = store.stage(_payload("new"), MANIFEST)
	assert_false(store.commit(ticket).ok)
	assert_eq(files.data[_path("primary.json")], primary)
	assert_eq(files.data[_path("previous.json")], previous)
	assert_true(store.commit(ticket).ok)
	files.data[_path("primary.json")] = files.data[_path("primary.json")].replace("original", "tampered")
	assert_true(store.load_latest(MANIFEST).fallback)

func test_generation_encoding_and_exhaustion_do_not_silently_normalize() -> void:
	_seed_pair()
	var original: String = files.data[_path("primary.json")]
	for value: String in ["0", "-1", "01", "9223372036854775808"]:
		var record: Dictionary = JSON.parse_string(original) as Dictionary
		record.generation = value
		record.erase("digest")
		record.digest = JSON.stringify(record, "", true).sha256_text()
		files.data[_path("primary.json")] = JSON.stringify(record, "", true)
		assert_true(store.load_latest(MANIFEST).fallback, value)
	var maximum: Dictionary = JSON.parse_string(original) as Dictionary
	maximum.generation = "9223372036854775807"
	maximum.erase("digest")
	maximum.digest = JSON.stringify(maximum, "", true).sha256_text()
	files.data[_path("primary.json")] = JSON.stringify(maximum, "", true)
	var reopened: CheckpointStore = CheckpointStore.new(DIRECTORY, files)
	assert_true(reopened.begin_run("run-a").ok)
	assert_eq(reopened.stage(_payload("overflow"), MANIFEST), 0)

func test_real_disk_reopen_previous_and_raw_corrupt_bytes_copy() -> void:
	var directory: String = "user://checkpoint-store-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var disk: CheckpointStore = CheckpointStore.new(directory)
	assert_true(disk.begin_run("disk-run").ok)
	assert_true(disk.commit(disk.stage(_payload("first"), MANIFEST)).ok)
	assert_true(disk.commit(disk.stage(_payload("second"), MANIFEST)).ok)
	var reopened: CheckpointStore = CheckpointStore.new(directory)
	assert_eq(reopened.load_latest(MANIFEST).record.payload, _payload("second"))
	var adapter: CheckpointFiles = CheckpointFiles.new()
	assert_true(adapter.read_text(directory.path_join("previous.json")).ok)
	var raw: PackedByteArray = PackedByteArray([255, 0, 254, 13, 10])
	var source: String = directory.path_join("raw-corrupt.bin")
	var output: FileAccess = FileAccess.open(source, FileAccess.WRITE)
	assert_not_null(output)
	output.store_buffer(raw)
	output.close()
	assert_eq(adapter.copy_verified(source, source + ".copy"), OK)
	assert_eq(FileAccess.get_file_as_bytes(source + ".copy"), raw)
	assert_true(reopened.invalidate("disk-run", "abandoned").ok)
	assert_eq(CheckpointStore.new(directory).load_latest(MANIFEST).reason, "run_invalidated")

func test_disk_read_hash_and_copy_enforce_the_same_size_limit() -> void:
	var directory: String = "user://checkpoint-store-tests/limit-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)
	var source: String = directory.path_join("oversized.bin")
	var output: FileAccess = FileAccess.open(source, FileAccess.WRITE)
	assert_not_null(output)
	output.seek(CheckpointFiles.MAX_BYTES)
	output.store_8(0)
	output.close()
	var adapter: CheckpointFiles = CheckpointFiles.new()
	assert_eq(adapter.read_text(source).reason, "size_limit")
	assert_eq(adapter.fingerprint(source), "")
	assert_ne(adapter.copy_verified(source, source + ".copy"), OK)
	assert_false(adapter.exists(source + ".copy"))

func test_real_disk_commit_failure_and_interruption_restore_exact_pair() -> void:
	for interrupted: bool in [false, true]:
		var directory: String = "user://checkpoint-store-tests/fault-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		var adapter: FaultDiskFiles = FaultDiskFiles.new()
		var disk: CheckpointStore = CheckpointStore.new(directory, adapter)
		assert_true(disk.begin_run("disk-run").ok)
		assert_true(disk.commit(disk.stage(_payload("one"), MANIFEST)).ok)
		assert_true(disk.commit(disk.stage(_payload("two"), MANIFEST)).ok)
		var primary: PackedByteArray = FileAccess.get_file_as_bytes(directory.path_join("primary.json"))
		var previous: PackedByteArray = FileAccess.get_file_as_bytes(directory.path_join("previous.json"))
		adapter.interrupt_primary = interrupted
		if not interrupted: adapter.fail_source = "checkpoint.tmp"
		assert_false(disk.commit(disk.stage(_payload("failed"), MANIFEST)).ok)
		var reopened: CheckpointStore = CheckpointStore.new(directory)
		var loaded: Dictionary = reopened.load_latest(MANIFEST)
		assert_true(loaded.ok)
		assert_eq(loaded.recovered_write, interrupted)
		assert_eq(FileAccess.get_file_as_bytes(directory.path_join("primary.json")), primary)
		assert_eq(FileAccess.get_file_as_bytes(directory.path_join("previous.json")), previous)
		assert_false(FileAccess.file_exists(directory.path_join("transaction.json")))

func test_real_disk_failed_invalidation_then_verified_retry() -> void:
	var directory: String = "user://checkpoint-store-tests/marker-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var adapter: FaultDiskFiles = FaultDiskFiles.new()
	var disk: CheckpointStore = CheckpointStore.new(directory, adapter)
	assert_true(disk.begin_run("disk-run").ok)
	var ticket: int = disk.stage(_payload("saved"), MANIFEST)
	assert_true(disk.commit(ticket).ok)
	var marker: String = "invalid-" + "disk-run".sha256_text() + ".json"
	adapter.fail_source = marker + ".tmp"
	assert_false(disk.invalidate("disk-run", "terminal").ok)
	assert_false(disk.commit(ticket).ok)
	assert_eq(disk.load_latest(MANIFEST).reason, "invalidation_pending")
	assert_true(FileAccess.file_exists(directory.path_join(marker + ".tmp")))
	assert_false(FileAccess.file_exists(directory.path_join(marker)))
	var after_failure: CheckpointStore = CheckpointStore.new(directory)
	assert_eq(after_failure.load_latest(MANIFEST).reason, "invalidation_pending", "durable temporary intent blocks restart before final marker commit")
	assert_false(after_failure.begin_run("different-new-run").ok, "new identity still requires verified old-run invalidation")
	assert_true(disk.invalidate("disk-run", "terminal").ok)
	assert_eq(CheckpointStore.new(directory).load_latest(MANIFEST).reason, "run_invalidated")

func test_incomplete_durable_invalidation_intent_blocks_both_generations_after_reopen() -> void:
	_seed_pair()
	var marker: String = _path("invalid-" + "run-a".sha256_text() + ".json.tmp")
	files.data[marker] = "interrupted-write"
	files.data[_path("primary.json")] = "corrupt-primary"
	var reopened: CheckpointStore = CheckpointStore.new(DIRECTORY, files)
	assert_eq(reopened.load_latest(MANIFEST).reason, "invalidation_pending")
	assert_eq(reopened.inspect_latest().reason, "invalidation_pending")
	assert_false(reopened.begin_run("run-b").ok)
	assert_true(reopened.invalidate("run-a", "terminal").ok)
	assert_eq(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).reason, "run_invalidated")

func test_failure_before_any_intent_is_written_cannot_claim_cross_restart_invalidation() -> void:
	_seed_pair()
	var marker: String = "invalid-" + "run-a".sha256_text() + ".json.tmp"
	files.failures["write:" + marker] = 1
	assert_false(store.invalidate("run-a", "terminal").ok)
	assert_eq(store.load_latest(MANIFEST).reason, "invalidation_pending")
	assert_true(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).ok, "no write can mean no persistent intent; caller must report failure")
	assert_true(store.invalidate("run-a", "terminal").ok)
	assert_eq(CheckpointStore.new(DIRECTORY, files).load_latest(MANIFEST).reason, "run_invalidated")

func test_recovery_rejects_stale_primary_proof_and_other_run_previous() -> void:
	_seed_pair()
	var primary: Dictionary = store.load_latest(MANIFEST).record
	_save("new-primary")
	assert_eq(store.previous_after_rejection(MANIFEST, primary).reason, "recovery_primary_changed")
	primary = store.load_latest(MANIFEST).record
	var previous: Dictionary = JSON.parse_string(files.data[_path("previous.json")])
	previous.run_id = "other-run"
	previous.erase("digest")
	previous.digest = JSON.stringify(previous, "", true).sha256_text()
	files.data[_path("previous.json")] = JSON.stringify(previous, "", true)
	assert_eq(store.previous_after_rejection(MANIFEST, primary).reason, "recovery_identity_or_generation_mismatch")

func test_retired_rollback_copies_are_removed_only_after_commit_and_cleanup_failure_keeps_pair() -> void:
	_seed_pair()
	assert_false(files.exists(_path("transaction.json")))
	assert_false(files.exists(_path("primary.rollback")))
	assert_false(files.exists(_path("previous.rollback")))
	var old_primary: String = files.data[_path("primary.json")]
	files.failures["remove:primary.rollback"] = 1
	var result: Dictionary = await store.commit_sliced(store.stage(_payload("cleanup"), MANIFEST), _yield_frame)
	assert_true(result.ok)
	assert_eq(result.cleanup_pending, PackedStringArray(["primary.rollback"]))
	assert_eq(files.data[_path("previous.json")], old_primary)
	assert_eq(store.load_latest(MANIFEST).record.payload, _payload("cleanup"))
	assert_false(files.exists(_path("transaction.json")))
	assert_true(files.exists(_path("primary.rollback")))
	assert_false(files.exists(_path("previous.rollback")))
	_save("next")
	assert_false(files.exists(_path("primary.rollback")))

func _seed_pair() -> void:
	_save("one")
	_save("two")

func _save(label: String) -> void:
	assert_true(store.commit(store.stage(_payload(label), MANIFEST)).ok, label)

func _payload(label: String) -> Dictionary:
	return {"label": label, "nested": [{"value": "original"}], "values": [true, null, 0.25, "9223372036854775807", "-9223372036854775808"]}

func _path(name: String) -> String:
	return DIRECTORY.path_join(name)
