class_name CheckpointJob
extends RefCounted

## One owner retains a store until joined, or until a Web transaction completes without a Thread.
## Frozen values enter the worker; only an independent verified candidate may return.
var _thread: Thread
var use_threads: bool = not OS.has_feature("web")
var _web_pending: bool = false
var _web_done: bool = false
var _web_result: Dictionary = {}

func start_save(store: CheckpointStore, encoded: Dictionary, budget_usec: int) -> Error:
	if _thread != null or _web_pending: return ERR_BUSY
	if not use_threads:
		_web_pending = true
		_run_web.call_deferred(_save.bind(store, encoded, budget_usec), store)
		return OK
	_thread = Thread.new()
	var error: Error = _thread.start(_save.bind(store, encoded, budget_usec))
	if error != OK: _thread = null
	return error

func start_load(store: CheckpointStore, compatibility: Dictionary, budget_usec: int, resume_plan: Dictionary = {}) -> Error:
	if _thread != null or _web_pending: return ERR_BUSY
	if not use_threads:
		_web_pending = true
		_run_web.call_deferred(_load.bind(store, compatibility.duplicate(true), budget_usec, resume_plan.duplicate(true)), store)
		return OK
	_thread = Thread.new()
	var error: Error = _thread.start(_load.bind(store, compatibility, budget_usec, resume_plan.duplicate(true)))
	if error != OK: _thread = null
	return error

func is_done() -> bool:
	if _web_pending: return _web_done
	return _thread != null and not _thread.is_alive()

## Main thread joins before using any returned RefCounted graph or touching the store.
func finish() -> Dictionary:
	if _web_pending:
		if not _web_done: return RunCheckpointCodec.failure("job_not_done")
		_web_pending = false
		_web_done = false
		return _web_result
	if _thread == null: return RunCheckpointCodec.failure("job_not_started")
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	return result

func _run_web(operation: Callable, store: CheckpointStore) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	_web_result = operation.call()
	var committed: Dictionary = await store.sync()
	if not committed.ok: _web_result = RunCheckpointCodec.failure(committed.reason)
	_web_done = true

func _save(store: CheckpointStore, encoded: Dictionary, budget_usec: int) -> Dictionary:
	var session: RunCheckpointSession = RunCheckpointSession.new(store, encoded.manifest)
	session.runtime_only = true
	session.rebuild_budget_usec = budget_usec
	return session.save_encoded(encoded)

func _load(store: CheckpointStore, compatibility: Dictionary, budget_usec: int, resume_plan: Dictionary) -> Dictionary:
	var session: RunCheckpointSession = RunCheckpointSession.new(store, compatibility)
	session.runtime_only = true
	session.rebuild_budget_usec = budget_usec
	var result: Dictionary = session.load_candidate()
	if result.ok:
		var preparing: int = Time.get_ticks_usec()
		if not resume_plan.is_empty():
			result.resume_context["prepared"] = resume_plan.duplicate(true)
			if resume_plan.get("record_file", false):
				var header: Dictionary = TelemetryResume.header(result.run, result.resume_context, resume_plan.collection_context, resume_plan.commit_id)
				result.run.recorder.open_resume_file(resume_plan.record_directory, resume_plan.session_id, header.metadata.resume)
		result["resume_prepare_usec"] = Time.get_ticks_usec() - preparing
		var started: int = Time.get_ticks_usec()
		var history: CheckpointHistory = CheckpointHistory.new()
		history.prime(result.run)
		result["history"] = history
		result["history_prime_usec"] = Time.get_ticks_usec() - started
	return result
