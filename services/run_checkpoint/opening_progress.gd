extends RefCounted

## Owns the durable authorization for the row-sweep opening.
const WEB: Script = preload("res://services/run_checkpoint/checkpoint_web_persistence.gd")
const RECORD: String = '{"schema":"opening-progress-v1","unlocked":["row_sweep"]}'
const EMPTY_WEB: String = '{"schema":"checkpoint-web-files-v1","files":{}}'

var unlocked: bool = false
var _web: WEB
var _path: String
var _files: CheckpointFiles = CheckpointFiles.new()

func load_progress(directory: String) -> String:
	_path = directory.path_join("opening_progress.json")
	if OS.has_feature("web"):
		_web = WEB.new()
		_web.slot = "opening_progress"
		var loaded: Dictionary = await _web.open()
		if not loaded.ok: return loaded.reason
		unlocked = loaded.data == RECORD
		return "" if unlocked or loaded.data == EMPTY_WEB else "opening_progress_invalid"
	for path: String in [_path, _path + ".bak"]:
		var raw: Dictionary = _files.read_text(path)
		if raw.ok and raw.text == RECORD:
			unlocked = true
			return ""
	return "opening_progress_invalid" if _files.exists(_path) or _files.exists(_path + ".bak") else ""

func grant() -> String:
	if unlocked: return ""
	if _web != null:
		var saved: Dictionary = await _web.save(RECORD)
		if not saved.ok: return saved.reason
	else:
		var temporary: String = _path + ".tmp"
		if _files.write_text(temporary, RECORD) != OK: return "opening_progress_write_failed"
		if _files.read_text(temporary).get("text") != RECORD: return "opening_progress_verify_failed"
		if _files.replace(temporary, _path) != OK: return "opening_progress_replace_failed"
		_files.copy_verified(_path, _path + ".bak")
	unlocked = true
	return ""

static func eligible(run: RunController) -> bool:
	var state: RunState = run.state
	if not state.stage.enabled() or not state.is_game_over or not state.rule_error.is_empty(): return false
	if state.end_reason not in [&"board_full", &"challenge_completed"]: return false
	if state.stage.index > 0: return true
	if state.stage.history.is_empty(): return false
	var last: StageResult = state.stage.history.back()
	return last.stage_id == 1 and last.reason in [&"stage_passed", &"challenge_completed"]
