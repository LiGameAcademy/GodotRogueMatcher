extends RefCounted

## Browser storage/session adapters and explicit downloads; rules never depend on this service.
const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
const SINK: Script = preload("res://services/telemetry/web_telemetry_sink.gd")
const SESSION: Script = preload("res://services/telemetry/web_collection_session.gd")
const JOURNAL: Script = preload("res://services/telemetry/web_record_journal.gd")
var backend: BACKEND
var export_ready: bool = false
var preparing_export: bool = false
var _journals: Array[JOURNAL] = []
var _sinks: Array[SINK] = []
var _resume: Dictionary = {}
var _export_bytes: PackedByteArray = PackedByteArray()
var _export_name: String = ""

func _init(storage: BACKEND = null) -> void:
	backend = storage if storage != null else BACKEND.new()

func open() -> Dictionary:
	return await backend.open()

func make_sink(storage_id: String) -> TelemetrySink:
	var sink: SINK = SINK.new(storage_id, backend)
	var owner: WeakRef = weakref(self)
	sink.completion_state = func() -> Dictionary:
		var current: RefCounted = owner.get_ref() as RefCounted
		return current.call("_record_completion", storage_id) if current != null else {"ready": true, "error": "web_record_owner_closed"}
	_sinks.append(sink)
	return sink

func make_session() -> CollectionSession:
	return SESSION.new(backend)

func attach(recorder: RunRecorder, projector: TelemetryProjector) -> void:
	var sink: SINK = projector.sink as SINK
	if sink == null: return
	var storage_id: String = sink.path.trim_prefix("telemetry/").trim_suffix(".jsonl")
	var journal: JOURNAL = JOURNAL.new(storage_id, backend)
	journal.seed(recorder.records, _resume)
	recorder.record_appended.connect(journal.append)
	_journals.append(journal)

## A syntactically valid checkpoint trace alone is not evidence of a durable parent event.
func prepare_resume(run: RunController, checkpoint: Dictionary, context: String, commit_id: String) -> Dictionary:
	var verified: Dictionary = checkpoint.duplicate(true)
	var trace: Variant = verified.get("trace", {})
	if not trace is Dictionary or not _has_parent(trace): verified["trace"] = {"status": "parent_prefix_unavailable"}
	_resume = TelemetryResume.header(run, verified, context, commit_id).metadata.resume.duplicate(true)
	return verified

func finish_resume() -> void:
	_resume.clear()

func error() -> String:
	if not backend.error.is_empty(): return backend.error
	for sink: SINK in _sinks:
		if not sink.error.is_empty(): return sink.error
	for journal: JOURNAL in _journals:
		if not journal.error.is_empty(): return journal.error
	return ""

func pending() -> bool:
	if backend.pending(): return true
	for sink: SINK in _sinks:
		if sink.accepted_seq > sink.persisted_seq and sink.error.is_empty(): return true
	for journal: JOURNAL in _journals:
		if journal.pending(): return true
	return false

## First click prepares a fixed acknowledged snapshot; the next click downloads in a user gesture.
func prepare_export() -> Dictionary:
	if preparing_export: return {"ok": false, "reason": "web_export_busy"}
	if not backend.ready: return _export_failed("web_export_storage_unavailable")
	preparing_export = true
	export_ready = false
	_export_bytes.clear()
	var deadline: int = Time.get_ticks_msec() + 30000
	while pending() and error().is_empty() and Time.get_ticks_msec() < deadline:
		await (Engine.get_main_loop() as SceneTree).process_frame
	if pending() and error().is_empty():
		preparing_export = false
		return {"ok": false, "reason": "web_export_waiting"}
	var readback: Dictionary = await backend.snapshot()
	if not readback.ok: return _export_failed(readback.reason)
	var snapshot: Dictionary[String, String] = readback.files
	if snapshot.is_empty(): return _export_failed("web_export_no_saved_records")
	var directory: String = "user://web-collection-export"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _export_failed("web_export_directory_failed")
	_export_name = "web-records-" + str(Time.get_ticks_usec()) + ".zip"
	var path: String = directory.path_join(_export_name)
	var writer: ZIPPacker = ZIPPacker.new()
	if writer.open(path) != OK: return _export_failed("web_export_open_failed")
	var failed: bool = false
	var manifest: Dictionary = {"schema": "web-collection-export-v1", "snapshot_utc": Time.get_datetime_string_from_system(true), "error": error(), "files": {}}
	var names: Array[String] = snapshot.keys()
	names.sort()
	for name: String in names:
		var bytes: PackedByteArray = snapshot[name].to_utf8_buffer()
		if writer.start_file(name) != OK: failed = true
		elif writer.write_file(bytes) != OK: failed = true
		if writer.close_file() != OK: failed = true
		manifest.files[name] = {"bytes": bytes.size(), "sha256": snapshot[name].sha256_text()}
		await (Engine.get_main_loop() as SceneTree).process_frame
	if writer.start_file("export_manifest.json") != OK: failed = true
	elif writer.write_file(JSON.stringify(manifest).to_utf8_buffer()) != OK: failed = true
	if writer.close_file() != OK: failed = true
	if writer.close() != OK: failed = true
	if not failed: _export_bytes = FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	if failed or _export_bytes.is_empty(): return _export_failed("web_export_incomplete")
	preparing_export = false
	export_ready = true
	return {"ok": true, "reason": "", "incomplete": not String(manifest.error).is_empty()}

func download() -> String:
	if not export_ready or _export_bytes.is_empty() or not OS.has_feature("web"): return ""
	JavaScriptBridge.download_buffer(_export_bytes, _export_name, "application/zip")
	export_ready = false
	_export_bytes.clear()
	return _export_name

func _has_parent(trace: Dictionary) -> bool:
	if not trace.get("run_id") is String or not trace.get("segment_id") is String: return false
	if not TelemetrySchema.safe_id(trace.run_id) or not TelemetrySchema.safe_id(trace.segment_id): return false
	if not TelemetrySchema.valid_integer(trace.get("accepted_seq")) or int(trace.accepted_seq) <= 0: return false
	var files: Dictionary[String, String] = backend.files()
	for suffix: String in ["", "--" + trace.segment_id]:
		var name: String = "telemetry/" + String(trace.run_id) + suffix + ".jsonl"
		if not files.has(name): continue
		var reader: TelemetryReader = TelemetryReader.new()
		var events: Array[Dictionary] = reader.read_text(files[name])
		var index: int = int(trace.accepted_seq) - 1
		if index >= events.size(): continue
		var row: Dictionary = events[index]
		if row.get("run_id") == trace.run_id and row.get("session_id") == trace.segment_id and row.get("event_id") == trace.get("last_event_id") and RunSnapshot.digest(row) == trace.get("last_event_hash"):
			return true
	return false

func _export_failed(reason: String) -> Dictionary:
	preparing_export = false
	return {"ok": false, "reason": reason}

func _record_completion(storage_id: String) -> Dictionary:
	var path: String = "run_records/" + storage_id + ".jsonl"
	for journal: JOURNAL in _journals:
		if journal.path == path:
			var problem: String = String(journal.diagnostics().error)
			return {"ready": not journal.pending(), "error": problem}
	return {"ready": true, "error": "web_record_journal_missing"}
