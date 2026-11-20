extends SceneTree

## Each invocation is a different real process sharing only this probe's isolated files.
class MarkerFaultFiles extends CheckpointFiles:
	func replace(source: String, destination: String) -> Error:
		if source.get_file().begins_with("invalid-"): return ERR_CANT_CREATE
		return super.replace(source, destination)

const POLICY: Dictionary = {"rules": "process-probe-v1", "content": "process-probe-v1"}
const RUN_ID: String = "process-probe-run"
var _directory: String = ""
var _mode: String = ""
var _report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not args[1].begins_with("user://checkpoint-recovery-process/"):
		push_error("Expected mode and an isolated user://checkpoint-recovery-process/ directory")
		quit(2)
		return
	_mode = args[0]
	_directory = args[1]
	_report = {"mode": _mode, "pid": OS.get_process_id(), "engine": Engine.get_version_info(), "ok": false}
	match _mode:
		"prepare_pending": _prepare_pending()
		"inspect_pending": _inspect_pending(false)
		"retry_pending": _inspect_pending(true)
		"prepare_bad_pair": _prepare_bad_pair()
		"recover_bad_pair": _recover_bad_pair(false)
		"reopen_repaired": _recover_bad_pair(true)
		_: _report["error"] = "unknown_mode"
	var output: FileAccess = FileAccess.open("res://.godot/checkpoint-process-%s.json" % _mode, FileAccess.WRITE)
	output.store_string(JSON.stringify(_report, "\t", true, true))
	output.close()
	print("CHECKPOINT_PROCESS " + JSON.stringify(_report))
	quit(0 if _report.ok else 1)

func _prepare_pending() -> void:
	var store: CheckpointStore = CheckpointStore.new(_directory, MarkerFaultFiles.new())
	if not store.begin_run(RUN_ID).ok: return
	for label: String in ["older", "newer"]:
		if not store.commit(store.stage({"value": label}, POLICY)).ok: return
	var failed: Dictionary = store.invalidate(RUN_ID, "terminal")
	var marker: String = _directory.path_join("invalid-" + RUN_ID.sha256_text() + ".json")
	# Make structural fallback necessary as well: the pending marker must still win.
	var primary: FileAccess = FileAccess.open(_directory.path_join("primary.json"), FileAccess.WRITE)
	primary.store_string("interrupted-primary")
	primary.close()
	_report["failed_invalidation"] = failed
	_report["temporary_intent_exists"] = FileAccess.file_exists(marker + ".tmp")
	_report["final_marker_exists"] = FileAccess.file_exists(marker)
	var expected: Dictionary = {"primary_hash": _hash("primary.json"), "previous_hash": _hash("previous.json")}
	_save_expectation(expected)
	_report["ok"] = not failed.ok and _report.temporary_intent_exists and not _report.final_marker_exists

func _inspect_pending(retry: bool) -> void:
	var expected: Dictionary = _expectation()
	var store: CheckpointStore = CheckpointStore.new(_directory)
	var loaded: Dictionary = store.load_latest(POLICY)
	_report["load_reason"] = loaded.reason
	_report["new_run_reason"] = store.begin_run("different-process-run").reason
	_report["original_pair_unchanged"] = expected.primary_hash == _hash("primary.json") and expected.previous_hash == _hash("previous.json")
	_report["ok"] = loaded.reason == "invalidation_pending" and _report.original_pair_unchanged and _report.new_run_reason == "invalidation_pending"
	if retry:
		var finished: Dictionary = store.invalidate(RUN_ID, "terminal")
		_report["retry_ok"] = finished.ok
		_report["after_retry_reason"] = CheckpointStore.new(_directory).load_latest(POLICY).reason
		_report["ok"] = _report.ok and finished.ok and _report.after_retry_reason == "run_invalidated"

func _normal() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	run.initialize()
	run.recorder = RunRecorder.new()
	run.recorder.begin(run, "checkpoint_process_probe", false)
	return run

func _prepare_bad_pair() -> void:
	var run: RunController = _normal()
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(_directory), RunCheckpointCodec.manifest(run))
	if not session.save(run).ok: return
	var expected: Dictionary = {"state": RunSnapshot.capture(run)}
	if not run.execute_command(GreedyBot.new(23).choose(run)).accepted: return
	for index: int in range(30):
		if RunCheckpointCodec.safety_error(run).is_empty(): break
		run.advance()
	if not session.save(run).ok: return
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("primary.json")))
	var payload: Dictionary = JSON.parse_string(record.payload.payload_json)
	payload.state_hash = "broken-endpoint-hash"
	record.payload.payload_json = JSON.stringify(payload, "", true, true)
	record.erase("digest")
	record.digest = JSON.stringify(record, "", true).sha256_text()
	var file: FileAccess = FileAccess.open(_directory.path_join("primary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "", true))
	file.close()
	expected["primary_hash"] = _hash("primary.json")
	expected["previous_hash"] = _hash("previous.json")
	_save_expectation(expected)
	_report["ok"] = true

func _recover_bad_pair(repaired: bool) -> void:
	var expected: Dictionary = _expectation()
	var policy: Dictionary = RunCheckpointCodec.manifest(_normal())
	var session: RunCheckpointSession = RunCheckpointSession.new(CheckpointStore.new(_directory), policy)
	var loaded: Dictionary = session.load_candidate()
	_report["load_ok"] = loaded.ok
	if not loaded.ok:
		_report["error"] = loaded.reason
		return
	_report["fallback"] = loaded.fallback
	_report["snapshot_equal"] = RunSnapshot.capture(loaded.run) == expected.state
	_report["previous_hash_unchanged"] = _hash("previous.json") == expected.previous_hash
	_report["ok"] = _report.snapshot_equal and _report.previous_hash_unchanged and loaded.fallback == not repaired
	if not repaired:
		_report["bad_primary_unchanged_on_load"] = _hash("primary.json") == expected.primary_hash
		var saved: Dictionary = session.save(loaded.run)
		_report["save_ok"] = saved.ok
		_report["verified_backup_preserved_after_save"] = _hash("previous.json") == expected.previous_hash
		_report["bad_original_preserved"] = _hash("primary.json.corrupt-" + expected.primary_hash + ".json") == expected.primary_hash
		_report["ok"] = _report.ok and _report.bad_primary_unchanged_on_load and saved.ok and _report.verified_backup_preserved_after_save and _report.bad_original_preserved

func _hash(name: String) -> String:
	return FileAccess.get_sha256(_directory.path_join(name))

func _save_expectation(value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_directory.path_join("probe-expectation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()

func _expectation() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("probe-expectation.json")))
