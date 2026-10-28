extends GutTest

## Audits real Game pause/skip at the required fuse-marker boundary without changing rules.
const HOST: PackedScene = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn")
const HOST_SCRIPT: Script = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.gd")
const OUTPUT: String = "res://.godot/issue130-interruptions/real_capture.json"
var _host: HOST_SCRIPT
var _probe: String = ""
var _triggered: bool = false
var _required_preserved: bool = false
var _skipped: Array[Dictionary] = []
var _records: Array[Dictionary] = []

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	_host = HOST.instantiate() as HOST_SCRIPT
	add_child_autofree(_host)
	assert_true(await wait_until(func() -> bool: return not _host.loading, 6.0))
	_host.board.view.fuses_visualized.connect(_on_mark)
	_host.board.director.step_skip_requested.connect(_on_skip)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	_host.queue_free()
	_host = null
	await wait_process_frames(5)

func after_all() -> void:
	if DisplayServer.get_name() == "headless": return
	assert_eq(_records.size(), 8)
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir())), OK)
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert_not_null(file)
	if file == null: return
	file.store_string(JSON.stringify(_records, "\t"))
	file.flush()
	assert_eq(file.get_error(), OK)
	file.close()

func test_four_mode_pause_freezes_mark_children_rng_and_rejects_skip_until_resumed() -> void:
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			var baseline: String = await _baseline(fast, low)
			await _prepare(fast, low, "pause")
			_host.play_case()
			assert_true(await wait_until(func() -> bool: return _triggered and get_tree().paused, 6.0))
			var digest: String = RunSnapshot.digest(RunSnapshot.capture(_host.board.run))
			var count: int = (_host.get("_events") as Array).size()
			assert_eq(count, 2)
			var current: PresentationStep = _host.board.director.get("_current") as PresentationStep
			assert_eq(current.kind, PresentationStep.Kind.MARK_FUSES)
			_host.game.call("_request_skip")
			assert_false(_host.board.director.skip_score_requested)
			var hold: Tween = (_host.board.view.get("_presentation_tweens") as Array).back() as Tween
			var elapsed: float = hold.get_total_elapsed_time()
			await wait_process_frames(30)
			assert_almost_eq(hold.get_total_elapsed_time(), elapsed, 0.00001)
			assert_eq((_host.get("_events") as Array).size(), count)
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(_host.board.run)), digest)
			assert_same(_host.board.director.get("_current"), current)
			assert_false(_host.board.can_selected)
			_host.game.call("_toggle_pause")
			assert_false(get_tree().paused)
			assert_true(await wait_until(func() -> bool: return not _host.report.is_empty(), 8.0))
			assert_true(_host._sample_valid(_host.report))
			_assert_final(baseline)
			_store("pause", baseline, true)

func test_four_mode_skip_waits_for_mark_then_skips_only_descendants_without_rule_drift() -> void:
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			var baseline: String = await _baseline(fast, low)
			await _prepare(fast, low, "skip")
			await _host.play_case()
			assert_true(_triggered)
			assert_true(_required_preserved)
			assert_eq((_host.report.markers as Array).size(), 1)
			assert_eq((_host.report.events as Array).size(), 2, "dye/match play; skipped descendants have no normal visual dispatch")
			assert_eq(_skipped.size(), 2)
			for index: int in range(_skipped.size()):
				assert_eq(int(_skipped[index].kind), PresentationStep.Kind.MATCHES)
				assert_eq(int(_skipped[index].generation), index + 1)
				assert_eq(_skipped[index].cause, "explosion")
			_assert_final(baseline)
			_store("skip", baseline, _required_preserved)

func _baseline(fast: bool, low: bool) -> String:
	await _prepare(fast, low, "")
	await _host.play_case()
	assert_true(_host._sample_valid(_host.report))
	return str(_host.report.rules_digest)

func _prepare(fast: bool, low: bool, probe: String) -> void:
	_probe = ""
	await _host.load_case("composite_chain")
	_host.configure_modes(fast, low)
	_triggered = false
	_required_preserved = false
	_skipped.clear()
	_probe = probe

func _assert_final(baseline: String) -> void:
	assert_eq(str(_host.report.rules_digest), baseline)
	assert_eq(_host.board.run.state.rewards.consumed_count, 1)
	assert_eq(_host.board.run.state.pending_rewards, 0)
	assert_eq(_host.board.run.state.ledger.total, 60)
	assert_eq((_host.game.get_node("UILayer/HUD") as Hud).displayed_score, 60)
	assert_true(_host.report.input_restored)
	assert_true(_host.report.director_idle)
	assert_true(_host.report.view_idle)
	assert_eq(int(_host.report.live_effects), 0)
	assert_eq((_host.report.errors as Array).size(), 0)
	assert_eq(_host.report.rule_error, "")
	assert_eq(_host.report.presentation_error, "")
	assert_false(_host.board.director.skip_score_requested)
	for piece: PieceState in _host.board.rules.state.get_snapshot():
		assert_not_null(_host.board.view.get_piece(piece.piece_id))
		assert_same(_host.board.get_cell(piece.coordinate).piece, _host.board.view.get_piece(piece.piece_id))

func _store(probe: String, baseline: String, boundary_preserved: bool) -> void:
	_records.append({"probe": probe, "fast": _host.report.fast, "low": _host.report.low,
		"headless": DisplayServer.get_name() == "headless", "baseline_digest": baseline,
		"final_digest": _host.report.rules_digest, "score": _host.report.score,
		"consumed_rewards": _host.board.run.state.rewards.consumed_count,
		"input_restored": _host.report.input_restored, "required_boundary_preserved": boundary_preserved,
		"paused_frames": 30 if probe == "pause" else 0,
		"events": _host.report.events.duplicate(true), "markers": _host.report.markers.duplicate(true),
		"skipped": _skipped.duplicate(true), "wall_elapsed_ms": _host.report.wall_elapsed_ms,
		"author_readable": null, "author_wait_acceptable": null, "author_audio_clear": null})

func _on_mark(_pieces: Array[PieceState]) -> void:
	if _probe.is_empty() or _triggered: return
	_triggered = true
	if _probe == "pause": _host.game.call("_toggle_pause")
	elif _probe == "skip":
		_host.game.call("_request_skip")
		var current: PresentationStep = _host.board.director.get("_current") as PresentationStep
		_required_preserved = current.kind == PresentationStep.Kind.MARK_FUSES and current.policy == PresentationStep.Policy.COMPLETE_REQUIRED and _skipped.is_empty() and not _host.board.can_selected

func _on_skip(step: PresentationStep, _epoch: int, _token: int) -> void:
	if step.matches.is_empty():
		_skipped.append({"kind": step.kind, "cause": "missing", "generation": -1})
	else:
		_skipped.append({"kind": step.kind, "cause": String(step.matches[0].cause), "generation": step.matches[0].generation})
