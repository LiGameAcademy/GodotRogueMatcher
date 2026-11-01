extends RefCounted

## Binds a frozen snapshot to one exact acknowledged telemetry row, never the latest live state.
## Resume reads only acknowledged backend files or existing native files; missing evidence is unknown.
static func confirm(trace: Dictionary, projectors: Array[TelemetryProjector]) -> Dictionary:
	if not _identity(trace): return {}
	for projector: TelemetryProjector in projectors:
		var target: int = String(trace.accepted_seq).to_int()
		if projector.events.size() < target: continue
		var row: Dictionary = projector.events[target - 1]
		if row.get("session_id") != trace.segment_id or row.get("run_id") != trace.run_id: continue
		if row.get("event_id") != trace.get("last_event_id") or RunSnapshot.digest(row) != trace.get("last_event_hash") or row.payload.get("snapshot_state_hash") != trace.get("snapshot_state_hash"): return {}
		var deadline: int = Time.get_ticks_msec() + 3000
		while int(projector.sink.diagnostics().persisted_seq) < target and projector.error.is_empty() and String(projector.sink.diagnostics().error).is_empty() and Time.get_ticks_msec() < deadline:
			await (Engine.get_main_loop() as SceneTree).process_frame
		if int(projector.sink.diagnostics().persisted_seq) < target or not projector.error.is_empty() or not String(projector.sink.diagnostics().error).is_empty(): return {}
		var confirmed: Dictionary = trace.duplicate(true)
		# Pin the durable parent to this frozen row even when later rows are already acknowledged.
		confirmed.persisted_seq = confirmed.accepted_seq
		return confirmed
	return {}

static func parent(trace: Dictionary, files: Dictionary[String, String]) -> Dictionary:
	if not _identity(trace): return {}
	for suffix: String in ["", "--" + trace.segment_id]:
		var path: String = "telemetry/" + String(trace.run_id) + suffix + ".jsonl"
		if not files.has(path): continue
		var reader: TelemetryReader = TelemetryReader.new()
		var rows: Array[Dictionary] = reader.read_text(files[path])
		var index: int = String(trace.accepted_seq).to_int() - 1
		if reader.error not in ["", "incomplete_telemetry_no_complete_ending"] or index >= rows.size(): continue
		var row: Dictionary = rows[index]
		if row.session_id == trace.segment_id and row.run_id == trace.run_id and row.event_id == trace.get("last_event_id") and RunSnapshot.digest(row) == trace.get("last_event_hash") and row.payload.get("snapshot_state_hash") == trace.get("snapshot_state_hash"): return row.duplicate(true)
	return {}

static func native_parent(trace: Dictionary, directory: String) -> Dictionary:
	if not _identity(trace): return {}
	var files: Dictionary[String, String] = {}
	for suffix: String in ["", "--" + trace.segment_id]:
		var name: String = String(trace.run_id) + suffix + ".jsonl"
		var file: FileAccess = FileAccess.open(directory.path_join(name), FileAccess.READ)
		if file == null or file.get_length() > 16 * 1024 * 1024: continue
		files["telemetry/" + name] = file.get_as_text()
	return parent(trace, files)

static func _identity(trace: Dictionary) -> bool:
	for key: String in ["run_id", "segment_id"]:
		if not trace.get(key) is String or not TelemetrySchema.safe_id(trace[key]): return false
	return TelemetrySchema.valid_integer(trace.get("accepted_seq")) and String(trace.accepted_seq).to_int() > 0
