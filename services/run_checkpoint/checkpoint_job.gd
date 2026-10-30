class_name CheckpointJob
extends RefCounted

## One desktop worker owns a store until joined. It never receives an active scene/run.
## Frozen values enter the worker; only an independent verified candidate may return.
var _thread: Thread

func start_save(store: CheckpointStore, encoded: Dictionary, budget_usec: int) -> Error:
	if _thread != null: return ERR_BUSY
	_thread = Thread.new()
	var error: Error = _thread.start(_save.bind(store, encoded, budget_usec))
	if error != OK: _thread = null
	return error

func start_load(store: CheckpointStore, compatibility: Dictionary, budget_usec: int) -> Error:
	if _thread != null: return ERR_BUSY
	_thread = Thread.new()
	var error: Error = _thread.start(_load.bind(store, compatibility, budget_usec))
	if error != OK: _thread = null
	return error

func is_done() -> bool:
	return _thread != null and not _thread.is_alive()

## Main thread joins before using any returned RefCounted graph or touching the store.
func finish() -> Dictionary:
	if _thread == null: return RunCheckpointCodec.failure("job_not_started")
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	return result

func _save(store: CheckpointStore, encoded: Dictionary, budget_usec: int) -> Dictionary:
	var session: RunCheckpointSession = RunCheckpointSession.new(store, encoded.manifest)
	session.runtime_only = true
	session.rebuild_budget_usec = budget_usec
	return session.save_encoded(encoded)

func _load(store: CheckpointStore, compatibility: Dictionary, budget_usec: int) -> Dictionary:
	var session: RunCheckpointSession = RunCheckpointSession.new(store, compatibility)
	session.runtime_only = true
	session.rebuild_budget_usec = budget_usec
	var result: Dictionary = session.load_candidate()
	if result.ok:
		var started: int = Time.get_ticks_usec()
		var history: CheckpointHistory = CheckpointHistory.new()
		history.prime(result.run)
		result["history"] = history
		result["history_prime_usec"] = Time.get_ticks_usec() - started
	return result
