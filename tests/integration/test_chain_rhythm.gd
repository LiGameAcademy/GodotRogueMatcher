extends GutTest

## Audits real short/long-chain order, score uniqueness, mode equivalence and interruption.
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

func test_long_chain_and_overlap_keep_six_stages_and_unique_union_in_four_modes() -> void:
	for key: String in ["long_chain", "shape_chain"]:
		var baseline: String = ""
		for fast: bool in [false, true]:
			for reduced: bool in [false, true]:
				await _host.load_case(key)
				_host.configure_modes(fast, reduced)
				var sources: Array[int] = []
				for at: Vector2i in [Vector2i(5, 5), Vector2i(6, 4), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 0)]:
					sources.append(_host.board.rules.state.get_piece_id(at))
				await _host.play_case()
				var sample: Dictionary = _host.report
				assert_true(_host._sample_valid(sample), key)
				var events: Array = sample.events
				assert_eq(events.size(), 6)
				assert_eq(bool(sample.input_restored), key == "long_chain")
				assert_eq(bool(sample.reward_waiting), key == "shape_chain")
				assert_eq(bool(sample.reward_popup), key == "shape_chain")
				assert_eq((sample.cues as Array).count("match"), 1)
				var removed: Dictionary[int, bool] = {}
				var centers: Array[Vector2i] = [Vector2i(5, 4), Vector2i(6, 4), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 0)]
				for index: int in range(events.size()):
					var event: Dictionary = events[index]
					assert_eq(int(event.generation), index)
					for id: int in event.removed_ids:
						assert_false(removed.has(id), "each entity leaves once")
						removed[id] = true
					if index > 0:
						assert_eq(int(event.source_id), sources[index - 1])
						assert_eq(event.center, [centers[index - 1].x, centers[index - 1].y])
						assert_gt(float(event.at_ms), float(events[index - 1].at_ms))
				var first: Dictionary = events[0]
				assert_eq(int(first.removed), 7 if key == "shape_chain" else 5)
				var shapes: Array[String] = []
				for hit: Dictionary in first.hits:
					if str(hit.shape_id) not in shapes: shapes.append(str(hit.shape_id))
				assert_has(shapes, "line")
				if key == "shape_chain": assert_has(shapes, "l")
				else: assert_eq(shapes, ["line"])
				assert_has(sample.cues, "blast")
				assert_has(sample.cues, "sweep")
				assert_null(sample.author_audio_clear)
				if baseline.is_empty(): baseline = str(sample.rules_digest)
				else: assert_eq(str(sample.rules_digest), baseline)

func test_long_capture_rejects_missing_geometry_duplicate_removal_and_wrong_generation() -> void:
	await _host.load_case("shape_chain")
	_host.configure_modes(true, true)
	await _host.play_case()
	assert_true(_host._sample_valid(_host.report))
	var geometry: Dictionary = _host.report.duplicate(true)
	geometry.events[0].hits = []
	assert_false(_host._sample_valid(geometry))
	var duplicate: Dictionary = _host.report.duplicate(true)
	duplicate.events[2].removed_ids = duplicate.events[1].removed_ids.duplicate()
	assert_false(_host._sample_valid(duplicate))
	var generation: Dictionary = _host.report.duplicate(true)
	generation.events[3].generation = 0
	assert_false(_host._sample_valid(generation))

func test_playback_geometry_is_detached_from_rule_result_and_shared_template() -> void:
	var run: RunController = HOST_SCRIPT.CASES.create("shape_chain")
	var groups: Array[BoardMatchGroup] = []
	var moved: BoardMoveResult = run.state.rules.move_piece(run.state.rules.state.get_piece_id(Vector2i(5, 5)), Vector2i(5, 4))
	assert_eq(moved.failure, BoardMoveResult.Failure.NONE)
	groups = run.state.rules.find_matches_at(Vector2i(5, 4))
	var results: Array[MatchResult] = run.abilities.resolve(groups)
	var steps: Array[PresentationStep] = PlaybackPlanBuilder.matches(results)
	var frozen: MatchResult = steps[0].matches[0]
	assert_gt(frozen.hits.size(), 1)
	var original_ids: Array[int] = frozen.hits[0].piece_ids.duplicate()
	results[0].hits[0].piece_ids.clear()
	results[0].hits[0].coordinates.clear()
	assert_eq(frozen.hits[0].piece_ids, original_ids)
	assert_false(frozen.hits[0].coordinates.is_empty())
	frozen.hits[0].piece_ids.clear()
	assert_false(groups[0].hits[0].piece_ids.is_empty())
	run.retire()

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

func test_pause_freezes_sweep_before_blast_in_four_modes() -> void:
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			await _verify_sweep_pause(fast, low)

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

func test_long_chain_skip_finishes_same_action_in_four_modes() -> void:
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			await _verify_long_skip(fast, low)

func test_long_chain_retry_isolates_old_playback_in_four_modes() -> void:
	# Exercise Game's own restart. The fixture normally intercepts it to reload a case.
	_host.game.set("use_external_restart", false)
	watch_signals(_host.board.view)
	watch_signals(_host.board.view.score_floats)
	watch_signals(_host.game.get_node("GameFeedback"))
	watch_signals(_host.board.director)
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			await _verify_long_retry(fast, low)

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

func _verify_long_skip(fast: bool, low: bool) -> void:
	var mode: String = "fast=%s low=%s" % [fast, low]
	await _host.load_case("long_chain")
	_host.configure_modes(fast, low)
	_host.play_case()
	var finished: bool = await wait_until(func() -> bool: return not _host.report.is_empty(), 8.0)
	assert_true(finished, mode)
	if not finished:
		return
	assert_true(_host._sample_valid(_host.report), mode)
	var baseline: String = str(_host.report.rules_digest)
	await _host.load_case("long_chain")
	_host.configure_modes(fast, low)
	var director: PresentationDirector = _host.board.director
	var skipped: Array[int] = []
	var request: Callable = func(step: PresentationStep, _epoch: int, _token: int) -> void:
		if _is_long_sweep(step):
			_host.game.call_deferred("_request_skip")
	var observe_skip: Callable = func(step: PresentationStep, _epoch: int, _token: int) -> void:
		assert_eq(step.kind, PresentationStep.Kind.MATCHES, mode)
		if not step.matches.is_empty():
			skipped.append(step.matches.front().generation)
	director.step_requested.connect(request)
	director.step_skip_requested.connect(observe_skip)
	_host.play_case()
	finished = await wait_until(func() -> bool: return not _host.report.is_empty(), 8.0)
	director.step_requested.disconnect(request)
	director.step_skip_requested.disconnect(observe_skip)
	assert_true(finished, mode)
	if not finished:
		return
	var sample: Dictionary = _host.report
	var shown: Array[int] = []
	for event: Dictionary in sample.events:
		shown.append(int(event.generation))
	assert_eq(shown, [0, 1, 2], mode)
	assert_eq(skipped, [2, 3, 4, 5], mode)
	assert_eq(str(sample.rules_digest), baseline, mode)
	assert_eq(int(sample.score), 77, mode)
	assert_eq((_host.game.get_node("UILayer/HUD") as Hud).displayed_score, 77, mode)
	assert_true(sample.input_restored and sample.director_idle and sample.view_idle, mode)
	assert_eq(int(sample.live_effects), 0, mode)
	assert_eq(sample.errors, [], mode)
	assert_eq(sample.presentation_error, "", mode)
	assert_false(director.skip_score_requested, mode)
	_assert_view_matches_rules(_host.board, mode)

func _verify_long_retry(fast: bool, low: bool) -> void:
	var mode: String = "fast=%s low=%s" % [fast, low]
	await _host.load_case("long_chain")
	_host.configure_modes(fast, low)
	var board: Board = _host.board
	var director: PresentationDirector = board.director
	var feedback: GameFeedback = _host.game.get_node("GameFeedback") as GameFeedback
	var old_id: String = board.run.state.run_id
	var old_steps: Array[Vector2i] = []
	var capture: Callable = func(step: PresentationStep, epoch: int, token: int) -> void:
		if _is_long_sweep(step):
			old_steps.append(Vector2i(epoch, token))
	director.step_requested.connect(capture)
	var old_results: Array[bool] = []
	_move_long_chain(old_results)
	var reached: bool = await wait_until(func() -> bool: return not old_steps.is_empty(), 6.0)
	director.step_requested.disconnect(capture)
	assert_true(reached, mode)
	if not reached:
		return
	var old_step: Vector2i = old_steps.front()
	assert_true(director.is_current(old_step.x, old_step.y), mode)
	assert_eq(board.run.state.ledger.total, 77, mode)
	assert_false(board.can_selected, mode)
	var old_effects: Array[Node] = board.view.get_children().filter(func(node: Node) -> bool:
		return node is LineClearVisual or node is ExplosionVisual or (node is ChessPiece and (node as ChessPiece).is_eliminating))
	var old_floats: Array[Node] = board.view.score_floats.get_children()
	assert_true(old_effects.any(func(node: Node) -> bool: return node is LineClearVisual), mode)
	assert_false(old_floats.is_empty(), mode)
	old_effects.append_array(old_floats)
	var voices: Array[AudioStreamPlayer] = (feedback.get("_players") as Array[AudioStreamPlayer]).duplicate()
	assert_false(voices.is_empty(), mode)
	var reset_counts: Array[Vector3i] = []
	var observe_reset: Callable = func() -> void:
		reset_counts.append(Vector3i(get_signal_emit_count(board.view, "match_visualized"),
			get_signal_emit_count(board.view.score_floats, "score_visualized"), get_signal_emit_count(feedback, "cue_played")))
		for voice: AudioStreamPlayer in voices:
			if is_instance_valid(voice):
				assert_false(voice.playing, mode)
				assert_false(voice.finished.is_connected(Callable(feedback, "_on_sound_finished").bind(voice)), mode)
	board.run_reset.connect(observe_reset, CONNECT_ONE_SHOT)
	var protected_steps: Array[bool] = []
	var try_old_completion: Callable = func(step: PresentationStep, epoch: int, token: int) -> void:
		if step.kind != PresentationStep.Kind.SPAWN or not protected_steps.is_empty():
			return
		for old_effect: Node in old_effects:
			assert_false(is_instance_valid(old_effect) and old_effect.is_inside_tree(), mode)
		assert_false(director.is_current(old_step.x, old_step.y), mode)
		assert_true(director.is_current(epoch, token), mode)
		assert_false(board.can_selected, mode)
		director.complete_step(old_step.x, old_step.y, true)
		assert_true(director.is_current(epoch, token), mode)
		director.complete_step(old_step.x, old_step.y, false)
		protected_steps.append(director.is_current(epoch, token) and not board.can_selected)
	director.step_requested.connect(try_old_completion)
	var failures_before: int = get_signal_emit_count(director, "playback_failed")
	var retry_results: Array[bool] = []
	_retry_long_game(retry_results)
	var restarted: bool = await wait_until(func() -> bool: return not retry_results.is_empty(), 8.0)
	director.step_requested.disconnect(try_old_completion)
	if board.run_reset.is_connected(observe_reset):
		board.run_reset.disconnect(observe_reset)
	assert_true(restarted, mode)
	if not restarted:
		return
	assert_eq(retry_results, [true], mode)
	assert_eq(old_results, [false], mode)
	assert_eq(protected_steps, [true], mode)
	assert_eq(reset_counts.size(), 1, mode)
	var fresh: RunController = board.run
	var fresh_state: String = RunSnapshot.digest(RunSnapshot.capture(fresh))
	assert_ne(fresh.state.run_id, old_id, mode)
	await get_tree().create_timer(0.8, true).timeout
	assert_same(board.run, fresh, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(fresh)), fresh_state, mode)
	assert_eq(fresh.state.action_id, 0, mode)
	assert_eq(fresh.state.ledger.total, 0, mode)
	assert_eq(fresh.state.pending_rewards, 0, mode)
	assert_eq(GameManager.score, 0, mode)
	assert_eq((_host.game.get_node("UILayer/HUD") as Hud).displayed_score, 0, mode)
	assert_false(is_instance_valid(UIManager.current_popup), mode)
	assert_eq(get_signal_emit_count(director, "playback_failed"), failures_before, mode)
	assert_eq(_host._live_effects(), 0, mode)
	assert_eq(board.view.score_floats.get_child_count(), 0, mode)
	assert_true(board.can_selected and not director.is_busy(), mode)
	if not reset_counts.is_empty():
		var reset: Vector3i = reset_counts.front()
		assert_eq(get_signal_emit_count(board.view, "match_visualized"), reset.x, mode)
		assert_eq(get_signal_emit_count(board.view.score_floats, "score_visualized"), reset.y, mode)
		for index: int in range(reset.z, get_signal_emit_count(feedback, "cue_played")):
			var cue: StringName = get_signal_parameters(feedback, "cue_played", index)[0]
			assert_false([&"match", &"blast", &"sweep", &"reward"].has(cue), mode)
	_assert_view_matches_rules(board, mode)
	var first: PieceState = board.rules.state.get_snapshot().front()
	await board._on_coordinate_pressed(first.coordinate)
	assert_not_null(board.selected_piece, mode)
	assert_same(board.selected_piece, board.view.get_piece(first.piece_id), mode)

func _assert_view_matches_rules(board: Board, mode: String) -> void:
	var occupied: int = 0
	var cells: Array[Cell] = board.view.get_cells()
	assert_eq(cells.size(), board.rules.state.columns * board.rules.state.rows, mode)
	for cell: Cell in cells:
		var expected: PieceState = board.rules.state.get_piece_at(cell.coordinate)
		if expected == null:
			assert_null(cell.piece, mode)
			continue
		assert_not_null(cell.piece, mode)
		if cell.piece == null:
			continue
		occupied += 1
		assert_eq(cell.piece.piece_id, expected.piece_id, mode)
		assert_eq(cell.piece.piece_type, expected.match_color, mode)
		assert_same(cell.piece, board.view.get_piece(expected.piece_id), mode)
	assert_eq(occupied, board.rules.state.get_piece_count(), mode)

func _is_long_sweep(step: PresentationStep) -> bool:
	return step.kind == PresentationStep.Kind.MATCHES and not step.matches.is_empty() and step.matches.front().generation == 2 and step.matches.front().cause == &"line_clear"

func _move_long_chain(results: Array[bool]) -> void:
	var board: Board = _host.board
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	results.append(await board.move_selected_piece(board.get_cell(Vector2i(5, 4))))

func _retry_long_game(results: Array[bool]) -> void:
	results.append(bool(await _host.game.call("_on_retry_requested")))

func _verify_sweep_pause(fast: bool, low: bool) -> void:
	var mode: String = "fast=%s low=%s" % [fast, low]
	await _host.load_case("row_blast")
	_host.configure_modes(fast, low)
	_host.play_case()
	var baseline_finished: bool = await wait_until(func() -> bool: return not _host.report.is_empty(), 6.0)
	assert_true(baseline_finished, mode)
	if not baseline_finished:
		return
	assert_true(_host._sample_valid(_host.report), mode)
	var baseline: String = str(_host.report.rules_digest)
	await _host.load_case("row_blast")
	_host.configure_modes(fast, low)
	_host.board.view.match_visualized.connect(_pause_at_sweep, CONNECT_ONE_SHOT)
	_host.play_case()
	var paused: bool = await wait_until(func() -> bool: return get_tree().paused, 4.0)
	assert_true(paused, mode)
	if not paused:
		if _host.board.view.match_visualized.is_connected(_pause_at_sweep):
			_host.board.view.match_visualized.disconnect(_pause_at_sweep)
		return
	var events: Array = (_host.get("_events") as Array).duplicate(true)
	assert_eq(events.size(), 1, mode)
	if not events.is_empty():
		assert_eq(events[0].cause, "line_clear", mode)
	var snapshot: String = RunSnapshot.digest(RunSnapshot.capture(_host.board.run))
	var sweep: LineClearVisual = null
	for child: Node in _host.board.view.get_children():
		if child is LineClearVisual:
			sweep = child as LineClearVisual
			break
	assert_not_null(sweep, mode)
	var paused_progress: float = 0.0
	var completed_progress: Array[float] = []
	if sweep != null:
		paused_progress = float(sweep.get("_progress"))
		sweep.tree_exiting.connect(func() -> void: completed_progress.append(float(sweep.get("_progress"))), CONNECT_ONE_SHOT)
	assert_false(_host.board.can_selected, mode)
	await get_tree().create_timer(0.4, true).timeout
	assert_true(is_instance_valid(sweep), mode)
	if is_instance_valid(sweep):
		assert_almost_eq(float(sweep.get("_progress")), paused_progress, 0.00001, mode)
	assert_true(completed_progress.is_empty(), mode)
	assert_eq(_host.get("_events"), events, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(_host.board.run)), snapshot, mode)
	assert_false(_host.board.can_selected, mode)
	_host.game.call("_toggle_pause")
	assert_false(get_tree().paused, mode)
	var finished: bool = await wait_until(func() -> bool: return not _host.report.is_empty(), 6.0)
	assert_true(finished, mode)
	if not finished:
		return
	assert_eq(completed_progress.size(), 1, mode)
	if not completed_progress.is_empty():
		assert_almost_eq(completed_progress[0], 1.0, 0.00001, mode)
	var sample: Dictionary = _host.report
	assert_true(_host._sample_valid(sample), mode)
	assert_eq(str(sample.rules_digest), baseline, mode)
	assert_eq(int(sample.score), 16, mode)
	assert_eq(int(sample.visualized_score), 16, mode)
	assert_true(sample.input_restored, mode)
	assert_eq(int(sample.live_effects), 0, mode)
	var causes: Array[String] = []
	for event: Dictionary in sample.events:
		causes.append(str(event.cause))
	assert_eq(causes, ["line_clear", "explosion"], mode)

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

func _pause_at_sweep(result: MatchResult, _cells: Array[Cell]) -> void:
	if result.cause == &"line_clear":
		_host.game.call("_toggle_pause")

func _pause_at_source(result: MatchResult, _cells: Array[Cell]) -> void:
	if _pause_once and result.cause == &"explosion":
		_pause_once = false
		get_tree().paused = true

func _reload_at_source(result: MatchResult, _cells: Array[Cell]) -> void:
	if _reload_once and result.cause == &"explosion":
		_reload_once = false
		_host.load_case.call_deferred("row_blast")
