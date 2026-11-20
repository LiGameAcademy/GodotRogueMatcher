extends RefCounted

## Persists the personal best and grants from the most recent settled run.
const ROLE: Script = preload("res://gameplay/openings/opening_role.gd")
const WEB: Script = preload("res://services/run_checkpoint/checkpoint_web_persistence.gd")
const RECORD: String = '{"schema":"opening-progress-v1","unlocked":["row_sweep"]}'
const EMPTY_WEB: String = '{"schema":"checkpoint-web-files-v1","files":{}}'

var unlocked: bool = false
var best: int = 0
var joined: Array[StringName] = []
var owned: Array[StringName] = []
var started: bool = false
var completed: bool = false
var settled_run: String = ""
var _web: WEB
var _path: String
var _files: CheckpointFiles = CheckpointFiles.new()

func load_progress(directory: String) -> String:
	unlocked = false
	best = 0
	joined.clear()
	owned.clear()
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
	if not value is Dictionary or value.get("schema") not in ["opening-progress-v2", "opening-progress-v3"]: return false
	if not value.get("settled") is String or not value.get("row") is bool: return false
	if value.settled != "" and not CheckpointStore._valid_id(value.settled): return false
	var points: int = 0
	var additions: Array[StringName] = []
	var roster: Array[StringName] = []
	if value.schema == "opening-progress-v3":
		if not value.get("best") is String or not value.best.is_valid_int(): return false
		points = String(value.best).to_int()
		if points < 0 or str(points) != value.best or not value.get("joined") is Array: return false
		for id: Variant in value.joined:
			if not id is String or id == "standard" or RunController.ROLES.find(id) == null or additions.has(StringName(id)): return false
			additions.append(StringName(id))
		if not value.get("owned") is Array: return false
		for id: Variant in value.owned:
			if not id is String or id == "standard" or RunController.ROLES.find(id) == null or roster.has(StringName(id)): return false
			roster.append(StringName(id))
		for id: StringName in additions:
			if not roster.has(id): return false
	owned = roster
	best = points
	joined = additions
	settled_run = value.settled
	unlocked = value.row
	started = true
	completed = not settled_run.is_empty() or unlocked
	return true

func begin_visit() -> String:
	if started or completed: return ""
	return await _write(_record("", false))

func available(id: StringName) -> bool:
	var role: ROLE = RunController.ROLES.find(id)
	return role != null and (id == &"standard" or owned.has(id) or (id == &"row_sweep" and unlocked))

func next_locked() -> ROLE:
	for role: ROLE in RunController.ROLES.ALL:
		if not available(role.id): return role
	return null

func finish_visit(run_id: String, row: bool, score: int = 0) -> String:
	if settled_run == run_id: return ""
	var highest: int = maxi(best, score)
	var additions: Array[StringName] = []
	for role: ROLE in RunController.ROLES.ALL:
		if not available(role.id) and (highest >= role.threshold or (role.id == &"row_sweep" and row)):
			additions.append(role.id)
	return await _write(_record(run_id, unlocked or row or additions.has(&"row_sweep"), highest, additions))

func _record(run_id: String, row: bool, points: int = 0, additions: Array[StringName] = []) -> String:
	var roster: Array[StringName] = owned.duplicate()
	for id: StringName in additions:
		if not roster.has(id): roster.append(id)
	if row and not roster.has(&"row_sweep"): roster.append(&"row_sweep")
	return JSON.stringify({"owned": roster, "schema": "opening-progress-v3", "settled": run_id, "row": row, "best": str(points), "joined": additions})

func grant() -> String:
	if unlocked: return ""
	return await _write(_record(settled_run, true, best, [&"row_sweep"]))

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
	if run.initialization != "normal" or not run.prototype_profile.is_empty(): return false
	if not state.stage.enabled() or not state.is_game_over or not state.rule_error.is_empty(): return false
	if state.end_reason not in [&"board_full", &"challenge_completed"]: return false
	if state.stage.index > 0: return true
	if state.stage.history.is_empty(): return false
	var last: StageResult = state.stage.history.back()
	return last.stage_id == 1 and last.reason in [&"stage_passed", &"challenge_completed"]
