extends GutTest

## Audits real short-chain order, score uniqueness, mode equivalence and interruption.
const HOST: PackedScene = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn")
const HOST_SCRIPT: Script = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.gd")
var _host: HOST_SCRIPT
var _pause_once: bool = false
var _reload_once: bool = false

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	_host = HOST.instantiate() as HOST_SCRIPT
	add_child_autofree(_host)
	assert_true(await wait_until(func() -> bool: return not _host.loading, 6.0))

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	_host.queue_free()
	_host = null
	await wait_process_frames(5)

func test_blast_to_sweep_preserves_order_score_and_four_mode_state() -> void:
	await _verify_case("blast_row", 61, [&"match", &"explosion", &"line_clear"])

func test_sweep_to_blast_preserves_reverse_order_and_four_mode_state() -> void:
	await _verify_case("row_blast", 16, [&"line_clear", &"explosion"])

func test_pause_freezes_chain_without_dispatching_children_or_opening_input() -> void:
	await _host.load_case("blast_row")
	_host.configure_modes(false, false)
	_pause_once = true
	_host.board.view.match_visualized.connect(_pause_at_source)
	_host.play_case()
	assert_true(await wait_until(func() -> bool: return get_tree().paused, 4.0))
	var before: int = (_host.get("_events") as Array).size()
	await wait_process_frames(8)
	assert_eq((_host.get("_events") as Array).size(), before)
	assert_false(_host.board.can_selected)
	get_tree().paused = false
	assert_true(await wait_until(func() -> bool: return not _host.report.is_empty(), 6.0))
	assert_eq(int(_host.report.score), 61)
	assert_true(_host.report.input_restored)
	assert_eq((_host.report.errors as Array).size(), 0)

func test_reload_during_chain_retires_old_wait_and_cannot_write_next_sample() -> void:
	await _host.load_case("blast_row")
	_reload_once = true
	_host.board.view.match_visualized.connect(_reload_at_source)
	watch_signals(_host)
	_host.play_case()
	assert_true(await wait_until(func() -> bool: return _host.case_key == "row_blast" and not _host.loading, 6.0))
	var run: RunController = _host.board.run
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(run))
	await wait_process_frames(20)
	assert_same(_host.board.run, run)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), snapshot)
	assert_true(_host.report.is_empty())
	assert_signal_not_emitted(_host, "sample_finished")
	await _host.play_case()
	assert_eq(int(_host.report.score), 16)
	assert_signal_emit_count(_host, "sample_finished", 1)

func test_capture_validation_rejects_bad_samples_and_write_failure_is_reported() -> void:
	await _host.play_case()
	assert_true(_host._sample_valid(_host.report))
	assert_false(_host._sample_valid({}))
	for key: String in ["input_restored", "director_idle", "view_idle"]:
		var invalid: Dictionary = _host.report.duplicate(true)
		invalid[key] = false
		assert_false(_host._sample_valid(invalid), key)
	var bad_score: Dictionary = _host.report.duplicate(true)
	bad_score.visualized_score = -1
	assert_false(_host._sample_valid(bad_score))
	var bad_order: Dictionary = _host.report.duplicate(true)
	(bad_order.events as Array).reverse()
	assert_false(_host._sample_valid(bad_order))
	var samples: Array[Dictionary] = [_host.report.duplicate(true)]
	assert_ne(_host._write_samples(samples, "user://absent-parent/chain_rhythm.json"), OK)
	assert_eq(_host._write_samples(samples, "user://chain_rhythm_write_test.json"), OK)
	assert_true(FileAccess.file_exists("user://chain_rhythm_write_test.json"))
	DirAccess.remove_absolute("user://chain_rhythm_write_test.json")

func _verify_case(key: String, score: int, expected: Array[StringName]) -> void:
	var baseline: String = ""
	for fast: bool in [false, true]:
		for reduced: bool in [false, true]:
			await _host.load_case(key)
			_host.configure_modes(fast, reduced)
			await _host.play_case()
			var result: Dictionary = _host.report
			assert_eq(int(result.score), score)
			assert_eq(int(result.visualized_score), score)
			assert_eq((result.errors as Array).size(), 0)
			assert_true(result.input_restored)
			assert_true(result.director_idle)
			assert_true(result.view_idle)
			assert_eq(int(result.live_effects), 0)
			assert_eq(result.rule_error, "")
			assert_eq(result.presentation_error, "")
			assert_null(result.author_source_readable)
			assert_null(result.author_wait_acceptable)
			var causes: Array[StringName] = []
			var identities: Dictionary[int, bool] = {}
			for event: Dictionary in result.events:
				causes.append(StringName(event.cause))
				assert_false(identities.has(int(event.event_id)))
				identities[int(event.event_id)] = true
				assert_true(event.input_blocked)
				if event.cause == "explosion": assert_eq(event.center, [5, 4])
				if event.cause == "line_clear": assert_eq(event.center, [6, 4] if key == "blast_row" else [1, 4])
			assert_eq(causes, expected)
			if baseline.is_empty(): baseline = str(result.rules_digest)
			else: assert_eq(str(result.rules_digest), baseline)

func _pause_at_source(result: MatchResult, _cells: Array[Cell]) -> void:
	if _pause_once and result.cause == &"explosion":
		_pause_once = false
		get_tree().paused = true

func _reload_at_source(result: MatchResult, _cells: Array[Cell]) -> void:
	if _reload_once and result.cause == &"explosion":
		_reload_once = false
		_host.load_case.call_deferred("row_blast")
