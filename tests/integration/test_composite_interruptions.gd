extends GutTest

## Audits real Game interruptions across the committed Composite presentation sequence.
const HOST: PackedScene = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn")
const HOST_SCRIPT: Script = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.gd")
const OUTPUT: String = "res://.godot/issue130-interruptions/real_capture.json"
const MARKED_IDS: Array[int] = [6, 8]
enum RetryBoundary { AFTER_DYE, DURING_MARK, BEFORE_BLAST }

class RetryProbe:
	var boundary: RetryBoundary
	var mode: String
	var old_run: RunController
	var counts_before: Vector3i
	var confirm: Callable
	var offer_id: int
	var skill_id: StringName
	var old_step: Vector2i
	var hold: Tween
	var hold_finished: Callable
	var triggered: bool = false
	var result: Array[bool] = []

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

func test_four_mode_retry_after_dye_clears_deferred_markers() -> void:
	await _verify_composite_retries(RetryBoundary.AFTER_DYE)

func test_four_mode_retry_during_mark_discards_old_visible_fuses() -> void:
	await _verify_composite_retries(RetryBoundary.DURING_MARK)

func test_four_mode_retry_before_blast_discards_queued_descendants() -> void:
	await _verify_composite_retries(RetryBoundary.BEFORE_BLAST)

func _verify_composite_retries(boundary: RetryBoundary) -> void:
	_host.game.set("use_external_restart", false)
	watch_signals(_host.board.view)
	watch_signals(_host.board.view.score_floats)
	watch_signals(_host.board)
	watch_signals(UIManager)
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			if not await _verify_composite_retry(fast, low, boundary):
				return

func _verify_composite_retry(fast: bool, low: bool, boundary: RetryBoundary) -> bool:
	await _prepare(fast, low, "")
	var probe: RetryProbe = RetryProbe.new()
	probe.boundary = boundary
	probe.mode = "fast=%s low=%s boundary=%s" % [fast, low, RetryBoundary.keys()[boundary]]
	var board: Board = _host.board
	probe.old_run = board.run
	probe.counts_before = _presentation_counts(board)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup, probe.mode)
	if popup == null or popup.offer == null or popup.offer.choices.is_empty():
		return false
	var flow: GameRewardFlow = _host.game.get("_reward_flow") as GameRewardFlow
	for connection: Dictionary in popup.skill_selected.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() == flow and callback.get_method() == &"_choose":
			probe.confirm = callback
			break
	assert_true(probe.confirm.is_valid(), probe.mode)
	if not probe.confirm.is_valid():
		return false
	probe.offer_id = popup.offer.offer_id
	probe.skill_id = popup.offer.choices[0].skill_id
	var observe_dye: Callable = _observe_dye_boundary.bind(probe)
	var observe_mark: Callable = _observe_mark_boundary.bind(probe)
	if boundary == RetryBoundary.AFTER_DYE:
		board.view.match_visualized.connect(observe_dye)
	else:
		board.director.step_requested.connect(observe_mark)
	(popup.options.get_child(0) as Button).pressed.emit()
	popup.confirm_button.pressed.emit()
	var finished: bool = await wait_until(func() -> bool: return not probe.result.is_empty(), 10.0)
	if boundary == RetryBoundary.AFTER_DYE:
		board.view.match_visualized.disconnect(observe_dye)
	else:
		board.director.step_requested.disconnect(observe_mark)
	if probe.hold != null and probe.hold_finished.is_valid() and probe.hold.finished.is_connected(probe.hold_finished):
		probe.hold.finished.disconnect(probe.hold_finished)
	probe.hold_finished = Callable()
	assert_true(finished, probe.mode)
	assert_eq(probe.result, [true], probe.mode)
	return finished and probe.result == [true]

func _observe_dye_boundary(result: MatchResult, _cells: Array[Cell], probe: RetryProbe) -> void:
	if probe.triggered or result.cause != &"dye":
		return
	var board: Board = _host.board
	var director: PresentationDirector = board.director
	assert_false(result.recolored.is_empty(), probe.mode)
	for changed: PieceState in result.recolored:
		var piece: ChessPiece = board.view.get_piece(changed.piece_id)
		assert_not_null(piece, probe.mode)
		if piece != null:
			assert_eq(piece.piece_type, changed.match_color, probe.mode)
	probe.old_step = Vector2i(int(director.get("_epoch")), int(director.get("_waiting_token")))
	assert_true(director.is_current(probe.old_step.x, probe.old_step.y), probe.mode)
	probe.triggered = true
	# Reduced effects can finish dye immediately and start the match in the same frame.
	_restart_composite.call_deferred(probe)

func _observe_mark_boundary(step: PresentationStep, epoch: int, token: int, probe: RetryProbe) -> void:
	if probe.triggered or step.kind != PresentationStep.Kind.MARK_FUSES:
		return
	var tweens: Array = _host.board.view.get("_presentation_tweens") as Array
	probe.hold = tweens.back() as Tween if not tweens.is_empty() else null
	assert_true(probe.hold != null and probe.hold.is_running(), probe.mode)
	if probe.hold == null or not probe.hold.is_running():
		probe.result.append(false)
		return
	probe.triggered = true
	probe.old_step = Vector2i(epoch, token)
	if probe.boundary == RetryBoundary.BEFORE_BLAST:
		# Board connects the hold completion first. The director queues the next dispatch.
		probe.hold_finished = _restart_composite.bind(probe)
		probe.hold.finished.connect(probe.hold_finished, CONNECT_ONE_SHOT)
	else:
		_restart_composite.call_deferred(probe)

func _restart_composite(probe: RetryProbe) -> void:
	if not is_instance_valid(_host):
		return
	var game: Node2D = _host.game
	var board: Board = _host.board
	var director: PresentationDirector = board.director
	assert_same(board.run, probe.old_run, probe.mode)
	if board.run != probe.old_run:
		probe.result.append(false)
		return
	var old_counts: Vector3i = _presentation_counts(board)
	_assert_retry_boundary(board, old_counts - probe.counts_before, probe)
	var marked_views: Array[ChessPiece] = []
	for id: int in MARKED_IDS:
		var piece: ChessPiece = board.view.get_piece(id)
		assert_not_null(piece, probe.mode)
		if piece != null:
			marked_views.append(piece)
			assert_eq(StringName(piece.get("_ability_kind")), &"" if probe.boundary == RetryBoundary.AFTER_DYE else &"引", probe.mode)
	var old_command: int = probe.old_run.last_command_id
	assert_eq(probe.old_run.state.rewards.consumed_count, 1, probe.mode)
	var popup_count: int = get_signal_emit_count(UIManager, "popup_opened")
	var reward_count: int = get_signal_emit_count(board, "reward_requested")
	var replayed: Array[bool] = []
	var replay_on_spawn: Callable = func(step: PresentationStep, epoch: int, token: int) -> void:
		if step.kind != PresentationStep.Kind.SPAWN or not replayed.is_empty():
			return
		var fresh: RunController = board.run
		assert_ne(fresh.state.run_id, probe.old_run.state.run_id, probe.mode)
		assert_false(board.can_selected, probe.mode)
		assert_true((board.view.get("_deferred_fuse_ids") as Array).is_empty(), probe.mode)
		for view: ChessPiece in marked_views:
			assert_false(is_instance_valid(view) and view.is_inside_tree(), probe.mode)
		var digest: String = RunSnapshot.digest(RunSnapshot.capture(fresh))
		_replay_composite_callbacks(director, probe)
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(fresh)), digest, probe.mode)
		replayed.append(director.is_current(epoch, token) and not board.can_selected)
	# Use the production seed port so the first real move deterministically reuses both marker IDs.
	board.new_run_seeds = NewRunSeedSource.new()
	board.new_run_seeds.entropy_provider = func() -> PackedByteArray: return PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	director.step_requested.connect(replay_on_spawn)
	var restarted: bool = bool(await game.call("_on_retry_requested"))
	if is_instance_valid(director) and director.step_requested.is_connected(replay_on_spawn):
		director.step_requested.disconnect(replay_on_spawn)
	if not is_instance_valid(_host) or _host.game != game:
		return
	assert_true(restarted, probe.mode)
	if not restarted:
		probe.result.append(false)
		return
	assert_eq(replayed, [true], probe.mode)
	var fresh: RunController = board.run
	var initial: String = RunSnapshot.digest(RunSnapshot.capture(fresh))
	_replay_composite_callbacks(director, probe)
	# The outer test uses GUT's awaiter; wait on actual scene frames here.
	for _frame: int in range(12):
		await get_tree().process_frame
		if not is_instance_valid(_host) or _host.game != game:
			return
	assert_same(board.run, fresh, probe.mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(fresh)), initial, probe.mode)
	assert_true(probe.old_run.is_retired(), probe.mode)
	assert_eq(probe.old_run.last_command_id, old_command, probe.mode)
	assert_eq(probe.old_run.state.rewards.consumed_count, 1, probe.mode)
	assert_eq(fresh.state.action_id, 0, probe.mode)
	assert_eq(fresh.state.ledger.total, 0, probe.mode)
	assert_eq((game.get_node("UILayer/HUD") as Hud).displayed_score, 0, probe.mode)
	assert_eq(fresh.state.pending_rewards, 0, probe.mode)
	assert_eq(fresh.state.rewards.consumed_count, 0, probe.mode)
	assert_null(fresh.state.rewards.active_offer, probe.mode)
	assert_false(is_instance_valid(UIManager.current_popup) or get_tree().paused, probe.mode)
	assert_true(board.can_selected and not director.is_busy() and not board.view.is_presenting(), probe.mode)
	assert_eq(_presentation_counts(board), old_counts, probe.mode)
	assert_eq(get_signal_emit_count(UIManager, "popup_opened"), popup_count, probe.mode)
	assert_eq(get_signal_emit_count(board, "reward_requested"), reward_count, probe.mode)
	assert_true((board.view.get("_deferred_fuse_ids") as Array).is_empty(), probe.mode)
	assert_true(await _move_fresh_piece(board), probe.mode)
	if not is_instance_valid(_host) or _host.game != game:
		return
	assert_eq(fresh.state.action_id, 1, probe.mode)
	for id: int in MARKED_IDS:
		var reused: ChessPiece = board.view.get_piece(id)
		assert_not_null(reused, probe.mode)
		if reused != null:
			assert_eq(StringName(reused.get("_ability_kind")), &"", probe.mode)
			assert_false(fresh.state.explosion.instances.has(id), probe.mode)
	probe.result.append(true)

func _assert_retry_boundary(board: Board, seen: Vector3i, probe: RetryProbe) -> void:
	var before_mark: bool = probe.boundary == RetryBoundary.AFTER_DYE
	var before_blast: bool = probe.boundary == RetryBoundary.BEFORE_BLAST
	if before_mark:
		assert_true(seen.x in [1, 2], probe.mode)
	else:
		assert_eq(seen.x, 2, probe.mode)
	if seen.x == 2:
		var next: MatchResult = get_signal_parameters(board.view, "match_visualized", probe.counts_before.x + 1)[0] as MatchResult
		assert_eq(next.cause, &"match", probe.mode)
	assert_eq(seen.y, 0 if before_mark else 1, probe.mode)
	var old_step_active: bool = board.director.is_current(probe.old_step.x, probe.old_step.y)
	assert_true(board.director.has_queued_steps() and not board.can_selected, probe.mode)
	var deferred: Array = board.view.get("_deferred_fuse_ids") as Array
	if before_mark:
		assert_eq(deferred, MARKED_IDS, probe.mode)
		var current: PresentationStep = board.director.get("_current") as PresentationStep
		if not old_step_active and current != null:
			var first_match: bool = current.kind == PresentationStep.Kind.MATCHES and not current.matches.is_empty() and current.matches.front().cause == &"match"
			assert_true(first_match, probe.mode)
			if first_match:
				probe.old_step = Vector2i(int(board.director.get("_epoch")), int(board.director.get("_waiting_token")))
	else:
		assert_eq(old_step_active, not before_blast, probe.mode)
		assert_true(deferred.is_empty(), probe.mode)
		assert_eq(probe.hold.is_running(), not before_blast, probe.mode)

func _presentation_counts(board: Board) -> Vector3i:
	return Vector3i(get_signal_emit_count(board.view, "match_visualized"),
		get_signal_emit_count(board.view, "fuses_visualized"),
		get_signal_emit_count(board.view.score_floats, "score_visualized"))

func _replay_composite_callbacks(director: PresentationDirector, probe: RetryProbe) -> void:
	director.complete_step(probe.old_step.x, probe.old_step.y, true)
	director.complete_step(probe.old_step.x, probe.old_step.y, false)
	probe.confirm.call(probe.offer_id, probe.skill_id)

func _move_fresh_piece(board: Board) -> bool:
	for piece: PieceState in board.rules.state.get_snapshot():
		for direction: Vector2i in BoardRules.MOVE_DIRECTIONS:
			var target: Vector2i = piece.coordinate + direction
			if board.rules.validate_move(piece.piece_id, target).is_valid():
				await board._on_coordinate_pressed(piece.coordinate)
				return await board.move_selected_piece(board.get_cell(target), 0.1)
	return false

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
