extends Node

## Observes real short/long chains; only fixture setup writes state, never playback callbacks.
signal sample_finished(report: Dictionary)
const OUTPUT: String = "res://.godot/issue130-chain-rhythm"
const CASES: Script = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_cases.gd")
const KEYS: Array[String] = CASES.KEYS
var loading: bool = true
var case_key: String = "blast_row"
var report: Dictionary = {}
var _epoch: int = 0
var _recording: bool = false
var _events: Array[Dictionary] = []
var _markers: Array[Dictionary] = []
var _cues: Array[StringName] = []
var _scores: Array[int] = []
var _seen: Dictionary[int, bool] = {}
var _errors: Array[String] = []
var _started_us: int = 0
## Read-only scene ports for integration tests and deterministic fixture commands.
@onready var board: Board = $Game/Board
@onready var game: Node2D = $Game
@onready var _feedback: GameFeedback = $Game/GameFeedback

func _ready() -> void:
	get_window().title = "技能连珠 · 连携节奏验收（1–5切例，Enter重播）"
	while not board.can_selected: await get_tree().process_frame
	board.view.match_visualized.connect(_on_match_visualized)
	board.view.fuses_visualized.connect(_on_fuses_visualized)
	board.view.score_floats.score_visualized.connect(_on_score_visualized)
	_feedback.cue_played.connect(_on_cue_played)
	game.restart_requested.connect(_reload)
	loading = false
	await load_case(KEYS[0])
	if "--capture-rhythm" in OS.get_cmdline_user_args(): await _capture_suite()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo or get_tree().paused: return
	if key.physical_keycode == KEY_1: load_case(KEYS[0])
	elif key.physical_keycode == KEY_2: load_case(KEYS[1])
	elif key.physical_keycode == KEY_3: load_case(KEYS[2])
	elif key.physical_keycode == KEY_4: load_case(KEYS[3])
	elif key.physical_keycode == KEY_5: load_case(KEYS[4])
	elif key.physical_keycode == KEY_ENTER:
		if not loading: _replay()
	else: return
	get_viewport().set_input_as_handled()

## Retires the previous run through the real board lifecycle, then installs a fixed case.
func load_case(key: String) -> void:
	if key not in KEYS or loading: return
	loading = true
	_epoch += 1
	_recording = false
	(game.get_node("PlaybackSettings") as PlaybackSettings).close()
	get_tree().paused = false
	UIManager.close_popup()
	_feedback.cancel()
	await board.start_game(BoardRules.new(BoardState.new(9, 9), 5), false)
	board.run.retire()
	board.run = CASES.create(key)
	board.rules = board.run.state.rules
	game.set("board_rules", board.rules)
	GameManager.reset_game(board.run)
	board.view.rebuild(board.rules.state.get_snapshot())
	board.refresh_ability_markers()
	board.can_selected = true
	game.call("_refresh_hud")
	case_key = key
	get_window().title = "技能连珠 · 连携验收 · " + CASES.title(key) + "（1–5切例，Enter重播）"
	report = {}
	if key == "composite_chain":
		board.run.recorder = RunRecorder.new()
		board.run.recorder.begin(board.run, "fixture_composite_rhythm", false)
		board.can_selected = false
		BoardRunFlow.continue_run(board, board.run)
		for _frame: int in range(600):
			if UIManager.current_popup is PopupSkillChoice and get_tree().paused:
				if not UIManager.current_popup.skill_selected.get_connections().is_empty(): break
			await get_tree().process_frame
	loading = false
	print("CHAIN_RHYTHM_READY ", key)

## Preserves independent fast/reduced-effects preferences without touching the fixture seed.
func configure_modes(fast: bool, reduced: bool) -> void:
	game.call("_set_fast", fast, false)
	game.call("_set_low_effects", reduced, false)

## Runs one real command and records facts; wall time is never a rule or acceptance gate.
func play_case() -> void:
	if loading or _recording: return
	if case_key == "composite_chain":
		if not UIManager.current_popup is PopupSkillChoice: return
	elif not board.can_selected or get_tree().paused: return
	var epoch: int = _epoch
	_recording = true
	_events.clear()
	_markers.clear()
	_cues.clear()
	_scores.clear()
	_seen.clear()
	_errors.clear()
	_started_us = Time.get_ticks_usec()
	var preferences: PlayerPreferences = game.get("preferences") as PlayerPreferences
	var fast: bool = preferences.fast
	var reduced: bool = preferences.low_effects
	if case_key == "composite_chain":
		var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
		popup._select(0)
		popup.confirm_selection()
		var deadline: int = Time.get_ticks_msec() + 10000
		while epoch == _epoch and (board.director.is_busy() or not board.can_selected or get_tree().paused):
			if Time.get_ticks_msec() >= deadline:
				_errors.append("composite_play_timeout")
				break
			await get_tree().process_frame
	elif case_key == "row_blast":
		await board._on_piece_activated(Vector2i(1, 4))
	else:
		board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
		await board.move_selected_piece(board.get_cell(Vector2i(5, 4)))
	if epoch != _epoch: return
	_recording = false
	var score_sum: int = 0
	for value: int in _scores: score_sum += value
	report = {"case": case_key, "fast": fast, "low": reduced,
		"events": _events.duplicate(true), "markers": _markers.duplicate(true),
		"seed": 145 if case_key == "composite_chain" else 128,
		"rule_records": _rule_records(), "cues": _cues.duplicate(), "errors": _errors.duplicate(),
		"score": GameManager.score, "visualized_score": score_sum,
		"rules_digest": RunSnapshot.digest(RunSnapshot.capture(board.run)),
		"input_restored": board.can_selected,
		"pending_rewards": board.run.state.pending_rewards,
		"reward_waiting": board.run.state.phase == RunState.Phase.REWARDS,
		"reward_popup": UIManager.current_popup is PopupSkillChoice, "director_idle": not board.director.is_busy(),
		"view_idle": not board.view.is_presenting(), "live_effects": _live_effects(),
		"rule_error": board.run.state.rule_error, "presentation_error": board.director.error,
		"wall_elapsed_ms": (Time.get_ticks_usec() - _started_us) / 1000.0,
		"headless": DisplayServer.get_name() == "headless",
		"author_source_readable": null, "author_wait_acceptable": null, "author_audio_clear": null}
	print("CHAIN_RHYTHM_RESULT ", JSON.stringify(report))
	sample_finished.emit(report.duplicate(true))

func _live_effects() -> int:
	var count: int = 0
	for child: Node in board.view.get_children():
		if (child is ExplosionVisual or child is LineClearVisual) and not child.is_queued_for_deletion(): count += 1
	return count

func _replay() -> void:
	await load_case(case_key)
	await play_case()

func _reload() -> void:
	load_case(case_key)

func _capture_suite() -> void:
	var samples: Array[Dictionary] = []
	var digests: Dictionary[String, String] = {}
	var valid: bool = true
	for key: String in KEYS:
		for fast: bool in [false, true]:
			for reduced: bool in [false, true]:
				await load_case(key)
				configure_modes(fast, reduced)
				await play_case()
				var sample: Dictionary = report.duplicate(true)
				var sample_valid: bool = _sample_valid(sample)
				if sample_valid:
					if digests.has(key): sample_valid = digests[key] == str(sample.rules_digest)
					else: digests[key] = str(sample.rules_digest)
				valid = valid and sample_valid
				sample["technical_valid"] = sample_valid
				samples.append(sample)
	var write_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if write_error == OK: write_error = _write_samples(samples, OUTPUT.path_join("real_capture.json"))
	if write_error != OK: push_error("Cannot write chain rhythm evidence: " + error_string(write_error))
	if not valid: push_error("Invalid chain rhythm sample; inspect evidence")
	get_tree().quit(0 if valid and write_error == OK else 1)

func _sample_valid(sample: Dictionary) -> bool:
	if sample.is_empty() or str(sample.get("case", "")) not in KEYS: return false
	if not (sample.errors as Array).is_empty(): return false
	if sample.rule_error != "" or sample.presentation_error != "": return false
	if not sample.director_idle or not sample.view_idle: return false
	if sample.case == "shape_chain":
		if sample.input_restored or not sample.reward_waiting or not sample.reward_popup: return false
		if int(sample.pending_rewards) != 1: return false
	elif not sample.input_restored or sample.reward_waiting or int(sample.pending_rewards) != 0: return false
	if int(sample.live_effects) != 0: return false
	var expected_score: int = {"blast_row": 61, "row_blast": 16, "long_chain": 77, "shape_chain": 111, "composite_chain": 60}[sample.case]
	if int(sample.score) != expected_score or int(sample.visualized_score) != expected_score: return false
	var expected: Array[String] = ["match", "explosion", "line_clear"]
	if sample.case == "composite_chain": expected.assign(["dye", "match", "explosion", "explosion"])
	if sample.case == "row_blast": expected.assign(["line_clear", "explosion"])
	if sample.case in ["long_chain", "shape_chain"]:
		expected.assign(["match", "explosion", "line_clear", "explosion", "line_clear", "explosion"])
	var events: Array = sample.events
	if events.size() != expected.size(): return false
	for index: int in range(events.size()):
		var event: Dictionary = events[index]
		if event.cause != expected[index] or not event.input_blocked: return false
	if sample.case == "composite_chain": return _composite_sample_valid(sample)
	if sample.case in ["long_chain", "shape_chain"]: return _long_sample_valid(sample)
	return true

func _long_sample_valid(sample: Dictionary) -> bool:
	var events: Array = sample.events
	var removed: Dictionary[int, bool] = {}
	var identities: Dictionary[int, bool] = {}
	var centers: Array[Vector2i] = [Vector2i(5, 4), Vector2i(6, 4), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 0)]
	for index: int in range(events.size()):
		var event: Dictionary = events[index]
		if int(event.generation) != index or identities.has(int(event.event_id)): return false
		identities[int(event.event_id)] = true
		for id: int in event.removed_ids:
			if removed.has(id): return false
			removed[id] = true
		if index > 0:
			if event.center != [centers[index - 1].x, centers[index - 1].y]: return false
			if float(event.at_ms) <= float(events[index - 1].at_ms): return false
			if not (events[index - 1].removed_ids as Array).has(int(event.source_id)): return false
	var first: Dictionary = events[0]
	if int(first.removed) != (7 if sample.case == "shape_chain" else 5): return false
	var shapes: Array[String] = []
	var union: Dictionary[int, bool] = {}
	for hit: Dictionary in first.hits:
		shapes.append(str(hit.shape_id))
		for id: int in hit.ids: union[id] = true
	if not shapes.has("line") or union.size() != int(first.removed): return false
	for id: int in first.removed_ids:
		if not union.has(id): return false
	if sample.case == "shape_chain" and not shapes.has("l"): return false
	return true

func _composite_sample_valid(sample: Dictionary) -> bool:
	var events: Array = sample.events
	var markers: Array = sample.markers
	if not events[0].new_fuses_visible.is_empty() or not events[1].new_fuses_visible.is_empty(): return false
	if markers.size() != 1 or markers[0].ids != [6, 8] or markers[0].visible_ids != [6, 8] or not markers[0].input_blocked: return false
	if float(markers[0].at_ms) <= float(events[1].at_ms) or float(markers[0].at_ms) >= float(events[2].at_ms): return false
	if events[2].center != [3, 2] or events[3].center != [3, 3]: return false
	if int(events[2].source_id) != 3 or int(events[3].source_id) != 6: return false
	if int(events[2].generation) != 1 or int(events[3].generation) != 2: return false
	for record: Dictionary in sample.rule_records:
		if record.kind == "RuleResult" and record.has("completed_leaves"):
			return record.completed_leaves == ["0.0", "1"] and record.skill_outcome == "applied"
	return false

func _new_fuse_ids() -> Array[int]:
	var ids: Array[int] = []
	if case_key == "composite_chain":
		for id: int in [6, 8]:
			var piece: ChessPiece = board.view.get_piece(id)
			if is_instance_valid(piece) and StringName(piece.get("_ability_kind")) == &"引": ids.append(id)
	return ids

func _rule_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if case_key == "composite_chain" and board.run.recorder != null:
		for record: Dictionary in board.run.recorder.records:
			if record.kind in ["CommandAttempt", "SkillAcquired", "RuleResult"]: records.append(record.duplicate(true))
	return records

func _write_samples(samples: Array[Dictionary], path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(samples, "\t"))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error

func _piece_ids(pieces: Array[PieceState]) -> Array[int]:
	var ids: Array[int] = []
	for piece: PieceState in pieces: ids.append(piece.piece_id)
	return ids

func _hit_data(hits: Array[BoardMatchHit]) -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for hit: BoardMatchHit in hits:
		var coordinates: Array[Array] = []
		for at: Vector2i in hit.coordinates: coordinates.append([at.x, at.y])
		data.append({"shape_id": String(hit.shape_id), "ids": hit.piece_ids.duplicate(),
			"origin": [hit.origin.x, hit.origin.y], "direction": [hit.direction.x, hit.direction.y],
			"coordinates": coordinates})
	return data

func _on_match_visualized(result: MatchResult, _cells: Array[Cell]) -> void:
	if not _recording: return
	var identity: int = result.score_entry.event_id
	if _seen.has(identity): _errors.append("duplicate_visual_event:%d" % identity)
	_seen[identity] = true
	if board.can_selected: _errors.append("input_open_during_match")
	_events.append({"event_id": identity, "cause": String(result.cause), "source_id": result.source_id,
		"center": [result.center.x, result.center.y], "generation": result.generation,
		"axis": result.line_axis, "removed": result.removed.size(),
		"score": result.score_entry.final_score, "new_fuses_visible": _new_fuse_ids(), "removed_ids": _piece_ids(result.removed),
		"hits": _hit_data(result.hits), "input_blocked": not board.can_selected,
		"at_ms": (Time.get_ticks_usec() - _started_us) / 1000.0})

func _on_score_visualized(entry: ScoreEntry, _origin: Vector2) -> void:
	if _recording: _scores.append(entry.final_score)

func _on_cue_played(cue: StringName) -> void:
	if _recording: _cues.append(cue)

func _on_fuses_visualized(pieces: Array[PieceState]) -> void:
	if _recording:
		_markers.append({"ids": _piece_ids(pieces), "visible_ids": _new_fuse_ids(), "input_blocked": not board.can_selected,
			"at_ms": (Time.get_ticks_usec() - _started_us) / 1000.0})
