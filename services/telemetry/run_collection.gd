class_name RunCollection
extends Node

signal status_changed(message: String)

var factory: TelemetryFactory
var session: CollectionSession = CollectionSession.new()
var run: RunController
var ui: String = "initializing"
var enabled: bool = false
var last_export: String = ""
var _heartbeat: float = 0.0
var _status: String = ""
var _past_failure: bool = false

func _process(delta: float) -> void:
	if not enabled: return
	_heartbeat += delta
	if _heartbeat >= factory.CONFIG.heartbeat_seconds:
		_heartbeat = 0.0
		for projector: TelemetryProjector in factory.projectors:
			if not projector.ended: projector.heartbeat()
		observe("heartbeat")
	flush(false)
	var current: String = save_status()
	if current != _status:
		_status = current
		status_changed.emit(current)

func _exit_tree() -> void:
	finish("scene_closed")
	if enabled: session.close("scene_closed")

func configure(context: String, destination: TelemetryFactory = null, recover_existing: bool = true) -> void:
	if enabled: return
	session = CollectionSession.new()
	factory = destination if destination != null else TelemetryFactory.new()
	factory.collection_context = context
	if recover_existing: factory.commit_id = str(ProjectSettings.get_setting("application/config/commit_id", "unknown"))
	if recover_existing and context == "editor_playtest": _identify_editor_build()
	factory.attached.connect(_attached)
	enabled = true
	session.start(factory, recover_existing)

## Closes the old observation segment without falsely abandoning a continued logical run.
func suspend_for_checkpoint() -> void:
	if not enabled: return
	flush()
	for projector: TelemetryProjector in factory.projectors:
		projector.close_segment("checkpoint_boundary", run.recorder.records.size() if run != null and run.recorder != null else 0)
		_past_failure = _past_failure or not projector.error.is_empty()
	for recorder: RunRecorder in factory.recorders:
		recorder.close_interrupted()
		_past_failure = _past_failure or not recorder.error.is_empty()
	session.close("checkpoint_boundary")
	_past_failure = _past_failure or not session.error.is_empty()
	enabled = false
	run = null
	status_changed.emit(save_status())

func checkpoint_trace(active: RunController) -> Dictionary:
	if not enabled or active != run or active.recorder == null or factory.projectors.is_empty(): return {}
	return factory.projectors.back().checkpoint_trace(active.recorder.records.size(), active.state.ledger.next_event_id())

## Values only; independent candidate prefix IO may be prepared by the desktop worker.
func plan_resume(record_file: bool) -> Dictionary:
	if not enabled or factory == null: return {}
	return {"session_id": TelemetryFactory.new().session_id, "record_file": record_file, "record_directory": factory.record_directory, "collection_context": factory.collection_context, "commit_id": factory.commit_id}

## Installs only new observation/file ownership on an already verified independent rule run.
func resume(context: String, active: RunController, checkpoint: Dictionary, record_file: bool) -> TelemetryProjector:
	var prepared: Dictionary = checkpoint.get("prepared", {})
	var destination: TelemetryFactory = TelemetryFactory.new(String(prepared.get("session_id", "")))
	var initial_collection: bool = factory == null
	if factory != null:
		destination.directory = factory.directory
		destination.record_directory = factory.record_directory
		destination.sink_factory = factory.sink_factory
		destination.commit_id = factory.commit_id
	if enabled: suspend_for_checkpoint()
	configure(context, destination, initial_collection)
	ui = ""
	var projector: TelemetryProjector = factory.resume(active, checkpoint, record_file)
	bind(active)
	session.append("run_registered", {"run_id": active.state.run_id, "storage_id": active.state.run_id + "--" + factory.session_id, "context": context, "resume": projector.events[0].get("resume", {}) if not projector.events.is_empty() else {}})
	flush()
	return projector

func bind(value: RunController) -> void:
	run = value
	if enabled:
		for index: int in range(factory.recorders.size() - 1, -1, -1):
			if factory.recorders[index].ended:
				_past_failure = _past_failure or not factory.recorders[index].error.is_empty() or not factory.projectors[index].error.is_empty()
				factory.recorders.remove_at(index)
				factory.projectors.remove_at(index)
	observe("run_initialized")

func location(value: String) -> void:
	ui = value
	if enabled:
		if not factory.projectors.is_empty(): factory.projectors.back().ui_location(value)
		observe("ui_changed")

func observe(kind: String) -> void:
	if not enabled: return
	var observation: Dictionary = {"ui": ui, "run_id": null, "observation": {}, "run_ended": false}
	if run != null:
		observation.run_id = run.state.run_id
		if not factory.projectors.is_empty():
			var projector: TelemetryProjector = factory.projectors.back()
			observation.observation = projector.observation(false)
			observation.run_ended = projector.ended
			if ui not in ["help", "start_menu", "result", "skill_pool", "settings"]: observation.ui = observation.observation.ui
	session.append(kind, observation)

func flush(force: bool = true) -> void:
	if not enabled: return
	for recorder: RunRecorder in factory.recorders:
		if not recorder.ended and (force or recorder.needs_flush): recorder.flush_pending()
	for projector: TelemetryProjector in factory.projectors:
		if not projector.ended and (force or projector.needs_flush): projector.flush_pending()
	session.flush()

func finish(reason: String) -> void:
	if not enabled: return
	observe("exit_requested:" + reason)
	if run != null and run.recorder != null and not run.recorder.ended:
		if not run.state.rule_error.is_empty(): run.recorder.finish(run, "rule_error", run.state.rule_error)
		elif run.state.is_game_over: run.recorder.finish(run, "completed", String(run.state.end_reason))
		else: run.recorder.finish(run, "abandoned", reason)
	flush()

func close(reason: String) -> void:
	finish(reason)
	if enabled: session.close(reason)

func save_status() -> String:
	if not enabled: return "本次未启用自动采集"
	if _past_failure: return "部分记录不完整；游戏仍可继续"
	if not session.error.is_empty(): return "记录保存失败；游戏仍可继续"
	for recorder: RunRecorder in factory.recorders:
		if not recorder.error.is_empty(): return "记录不完整；游戏仍可继续"
	for projector: TelemetryProjector in factory.projectors:
		if not projector.error.is_empty(): return "记录不完整；游戏仍可继续"
		if projector.sink is LocalJsonlSink:
			var sink: LocalJsonlSink = projector.sink as LocalJsonlSink
			var diagnostics: Dictionary = sink.diagnostics()
			if not String(diagnostics.error).is_empty(): return "记录不完整；游戏仍可继续"
			if sink.accepted_seq > sink.persisted_seq: return "记录等待保存…"
	return "记录已保存到本机 · 不上传"

func open_directory() -> void:
	if not enabled or OS.has_feature("web"): return
	var code: Error = OS.shell_open(ProjectSettings.globalize_path(factory.directory))
	if code != OK: status_changed.emit("打开记录目录失败")

func export_files() -> String:
	if not enabled or OS.has_feature("web"): return ""
	flush()
	var path: String = factory.directory.path_join("export-" + factory.session_id + "-" + str(Time.get_ticks_usec()) + ".zip")
	var writer: ZIPPacker = ZIPPacker.new()
	if writer.open(path) != OK:
		status_changed.emit("导出失败")
		return ""
	var failed: bool = false
	var groups: Dictionary[String, String] = {factory.directory: "telemetry", factory.directory.path_join("sessions"): "sessions", factory.record_directory: "run_records"}
	for directory: String in groups:
		if not DirAccess.dir_exists_absolute(directory): continue
		for name: String in DirAccess.get_files_at(directory):
			if not name.ends_with(".jsonl") and not name.ends_with(".summary.json"): continue
			var file: FileAccess = FileAccess.open(directory.path_join(name), FileAccess.READ)
			if file == null:
				failed = true
				continue
			if writer.start_file(groups[directory] + "/" + name) != OK: failed = true
			elif writer.write_file(file.get_buffer(file.get_length())) != OK: failed = true
			if writer.close_file() != OK: failed = true
			file.close()
	if writer.close() != OK: failed = true
	if failed:
		DirAccess.remove_absolute(path)
		status_changed.emit("导出不完整；原始记录仍保留")
		return ""
	last_export = path
	status_changed.emit("记录已导出，可在记录目录找到 ZIP")
	return path

func _attached(recorder: RunRecorder, projector: TelemetryProjector) -> void:
	recorder.record_appended.connect(func(row: Dictionary) -> void:
		if row.kind != "Header": return
		session.append("run_registered", {"run_id": row.run_id, "context": factory.collection_context})
		session.flush()
	)
	recorder.recording_finished.connect(func(_complete: bool) -> void:
		session.append("run_finalized", {"run_id": projector.events[0].run_id if not projector.events.is_empty() else "unknown", "summary_path": projector.summary_path, "error": projector.error})
		session.flush()
	)

func _identify_editor_build() -> void:
	# 本地编辑器只读自身仓库；导出包从发布配置注入commit_id，不依赖Git。
	var output: Array = []
	var root: String = ProjectSettings.globalize_path("res://")
	if not DirAccess.dir_exists_absolute(root.path_join(".git")) and not FileAccess.file_exists(root.path_join(".git")): return
	if OS.execute("git", ["-C", root, "rev-parse", "HEAD"], output, false, false) != 0 or output.is_empty(): return
	var revision: String = str(output[0]).strip_edges()
	if RegEx.create_from_string("^[0-9a-f]{40}$").search(revision) == null: return
	factory.commit_id = revision
	output.clear()
	if OS.execute("git", ["-C", root, "status", "--porcelain"], output, false, false) == 0 and not output.is_empty() and not str(output[0]).strip_edges().is_empty(): factory.commit_id += "+dirty"
