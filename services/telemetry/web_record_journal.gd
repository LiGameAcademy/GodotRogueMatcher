extends RefCounted

## Append-only rule evidence, paced independently of rule execution and checkpoint IO.
const BACKEND: Script = preload("res://services/telemetry/web_telemetry_backend.gd")
var path: String = ""
var error: String = ""
var accepted_seq: int = 0
var _backend: BACKEND
var _rows: Array[Dictionary] = []
var _next: int = 0
var _last: int = 0
var _busy: bool = false
var _resume: Dictionary = {}

func _init(storage_id: String, backend: BACKEND) -> void:
	_backend = backend
	path = "run_records/" + storage_id + ".jsonl"
	if not TelemetrySchema.safe_id(storage_id) or not _backend.reserve(path): error = "web_record_file_unavailable"

## Recorder-owned historical rows are immutable after append. Metadata is copied below.
func seed(records: Array[Dictionary], resume: Dictionary = {}) -> void:
	if _last != 0 or not error.is_empty(): return
	if records.size() > 4096:
		error = "web_record_prefix_limit"
		return
	_rows = records.duplicate()
	_last = records.size()
	_resume = resume.duplicate(true)
	if not _rows.is_empty(): _pump.call_deferred()

func append(row: Dictionary) -> void:
	if not error.is_empty(): return
	if not CommandCodec.valid_integer(row.get("seq")) or int(row.seq) != _last + 1:
		error = "web_record_sequence_mismatch"
		return
	if _rows.size() - _next >= 4096:
		error = "web_record_queue_limit"
		return
	_last += 1
	_rows.append(row)
	if not _busy: _pump.call_deferred()

func pending() -> bool:
	return _busy or _next < _rows.size() or _backend.persisted_sequence(path) < accepted_seq

func diagnostics() -> Dictionary:
	return {"accepted_seq": accepted_seq, "persisted_seq": _backend.persisted_sequence(path), "error": error if not error.is_empty() else _backend.error}

func _pump() -> void:
	if _busy or not error.is_empty(): return
	_busy = true
	var started: int = Time.get_ticks_usec()
	var processed: int = 0
	while _next < _rows.size():
		var row: Dictionary = _rows[_next]
		if row.get("seq") == "1" and not _resume.is_empty():
			row = row.duplicate(true)
			row.metadata["recording_resume"] = _resume.duplicate(true)
		var sequence: int = int(row.seq)
		if not _backend.append(path, JSON.stringify(row, "", true, true) + "\n", sequence):
			error = _backend.error if not _backend.error.is_empty() else "web_record_append_rejected"
			break
		accepted_seq = sequence
		_rows[_next] = {}
		_next += 1
		if _next >= 512:
			_rows = _rows.slice(_next)
			_next = 0
		processed += 1
		if processed >= 4 or Time.get_ticks_usec() - started >= 3000:
			await (Engine.get_main_loop() as SceneTree).process_frame
			started = Time.get_ticks_usec()
			processed = 0
	if _next == _rows.size():
		_rows.clear()
		_next = 0
	_busy = false
