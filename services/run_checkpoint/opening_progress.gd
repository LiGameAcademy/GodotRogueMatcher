extends RefCounted

## Owns the durable authorization for the row-sweep opening.
const WEB: Script = preload("res://services/run_checkpoint/checkpoint_web_persistence.gd")
const RECORD: String = '{"schema":"opening-progress-v1","unlocked":["row_sweep"]}'
const EMPTY_WEB: String = '{"schema":"checkpoint-web-files-v1","files":{}}'

var unlocked: bool = false
var started: bool = false
var completed: bool = false
var settled_run: String = ""
var _web: WEB
var _path: String
var _files: CheckpointFiles = CheckpointFiles.new()

func load_progress(directory: String) -> String:
	unlocked = false
	started = false
	completed = false
	settled_run = ""
	_path = directory.path_join("opening_progress.json")
	if OS.has_feature("web"):
		_web = WEB.new()
		_web.slot = "opening_progress"
		var loaded: Dictionary = await _web.open()
		if not loaded.ok: return loaded.reason
		return "" if loaded.data == EMPTY_WEB or _read(loaded.data) else "opening_progress_invalid"
	for path: String in [_path, _path + ".bak"]:
		var raw: Dictionary = _files.read_text(path)
		if raw.ok and _read(raw.text): return ""
	return "opening_progress_invalid" if _files.exists(_path) or _files.exists(_path + ".bak") else ""

func _read(text: String) -> bool:
	if text == RECORD:
		unlocked = true
		completed = true
		return true
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return false
	var value: Variant = parser.data
	if not value is Dictionary or value.get("schema") != "opening-progress-v2": return false
	if not value.get("settled") is String or not value.get("row") is bool: return false
	if value.settled != "" and not CheckpointStore._valid_id(value.settled): return false
	settled_run = value.settled
	unlocked = value.row
	started = true
	completed = not settled_run.is_empty() or unlocked
	return true

func begin_visit() -> String:
	return await _write(_record("", false))

func finish_visit(run_id: String, row: bool) -> String:
	if settled_run == run_id and (unlocked or not row): return ""
	return await _write(_record(run_id, unlocked or row))

func _record(run_id: String, row: bool) -> String:
	return JSON.stringify({"schema": "opening-progress-v2", "settled": run_id, "row": row})

func grant() -> String:
	if unlocked: return ""
	return await _write(RECORD)

func _write(text: String) -> String:
	if _web != null:
		var saved: Dictionary = await _web.save(text)
		if not saved.ok: return saved.reason
	else:
		var temporary: String = _path + ".tmp"
		if _files.write_text(temporary, text) != OK: return "opening_progress_write_failed"
		if _files.read_text(temporary).get("text") != text: return "opening_progress_verify_failed"
		if _files.replace(temporary, _path) != OK: return "opening_progress_replace_failed"
		_files.copy_verified(_path, _path + ".bak")
	_read(text)
	return ""

static func eligible(run: RunController) -> bool:
	var state: RunState = run.state
	if not state.stage.enabled() or not state.is_game_over or not state.rule_error.is_empty(): return false
	if state.end_reason not in [&"board_full", &"challenge_completed"]: return false
	if state.stage.index > 0: return true
	if state.stage.history.is_empty(): return false
	var last: StageResult = state.stage.history.back()
	return last.stage_id == 1 and last.reason in [&"stage_passed", &"challenge_completed"]
