class_name CollectionSession
extends RefCounted

var path: String = ""
var error: String = ""
var recovered: Array[String] = []
var _file: FileAccess
var _sequence: int = 0
var _closed: bool = false
var _pending: PackedByteArray = PackedByteArray()

func start(factory: TelemetryFactory) -> void:
	var directory: String = factory.directory.path_join("sessions")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "session_directory_failed"
		return
	_recover(factory, directory)
	path = directory.path_join(factory.session_id + ".jsonl")
	if FileAccess.file_exists(path):
		error = "session_already_exists"
		return
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		error = "session_open_failed"
		return
	append("session_started", {"session_id": factory.session_id, "pid": OS.get_process_id(), "context": factory.collection_context})
	flush()

func append(kind: String, payload: Dictionary) -> void:
	if _closed or _file == null or not error.is_empty(): return
	_sequence += 1
	var row: Dictionary = {"session_schema": "collection-session-v1", "seq": _sequence, "event": kind, "observed_at_utc": Time.get_datetime_string_from_system(true), "payload": payload}
	var bytes: PackedByteArray = (RunSnapshot.canonical(row) + "\n").to_utf8_buffer()
	if _pending.size() + bytes.size() > TelemetryFactory.CONFIG.maximum_queue_bytes:
		error = "session_queue_limit"
		return
	_pending.append_array(bytes)

func flush() -> void:
	if _file == null or _pending.is_empty() or not error.is_empty(): return
	_file.store_buffer(_pending)
	_file.flush()
	if _file.get_error() != OK: error = "session_flush_failed"
	else: _pending.clear()

func close(reason: String) -> void:
	if _closed: return
	append("session_closed", {"reason": reason})
	flush()
	if _file != null: _file.close()
	_file = null
	_closed = true

## 不以心跳超时判死。Windows枚举现存PID；其它平台不能确认时保留原文件。
func _recover(factory: TelemetryFactory, directory: String) -> void:
	if OS.get_name() != "Windows": return
	var output: Array = []
	var code: int = OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process).Id -join ','"], output, false, false)
	if code != 0 or output.is_empty(): return
	var live: PackedStringArray = []
	for found: RegExMatch in RegEx.create_from_string("[0-9]+").search_all(String(output[0])): live.append(found.get_string())
	if not live.has(str(OS.get_process_id())): return
	for name: String in DirAccess.get_files_at(directory):
		if not name.ends_with(".jsonl"): continue
		var rows: Array[Dictionary] = _read_session(directory.path_join(name))
		if rows.is_empty() or rows[0].get("event") != "session_started": continue
		var pid: String = str(rows[0].get("payload", {}).get("pid", ""))
		if not CommandCodec.valid_integer(pid) or live.has(pid): continue
		for row: Dictionary in rows:
			if row.get("event") != "run_registered": continue
			var id: String = str(row.get("payload", {}).get("run_id", ""))
			if not TelemetrySchema.safe_id(id): continue
			var source: String = factory.directory.path_join(id + ".jsonl")
			var destination: String = source + ".recovered.summary.json"
			if not FileAccess.file_exists(source) or FileAccess.file_exists(source + ".summary.json") or FileAccess.file_exists(destination): continue
			var result: Dictionary = TelemetrySummary.recover(source)
			if result.get("run_id") != id: continue
			var problem: String = TelemetrySummary.write_unique(destination, result)
			if problem.is_empty(): recovered.append(destination)
			else: error = problem

func _read_session(source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null: return result
	while not file.eof_reached():
		var line: String = file.get_line()
		if file.eof_reached(): break
		var json: JSON = JSON.new()
		if json.parse(line) != OK or not json.data is Dictionary: break
		var row: Dictionary = json.data
		if row.get("session_schema") != "collection-session-v1" or row.get("seq") != str(result.size() + 1): break
		if not row.get("payload") is Dictionary or not row.get("event") is String: break
		result.append(row)
	file.close()
	return result
