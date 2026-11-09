extends GutTest

## Checks frozen shape-chain rewards across presentation interruptions and confirmation.
const HOST: PackedScene = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn")
const HOST_SCRIPT: Script = preload("res://tools/chain_rhythm_acceptance/chain_rhythm_acceptance.gd")
var _host: HOST_SCRIPT

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

func test_shape_chain_skip_preserves_reward_and_consumes_once_in_four_modes() -> void:
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			var mode: String = "fast=%s low=%s" % [fast, low]
			var normal: Dictionary = await _play_and_choose(fast, low, false, mode)
			var skipped: Dictionary = await _play_and_choose(fast, low, true, mode)
			assert_false(normal.is_empty(), mode)
			assert_false(skipped.is_empty(), mode)
			assert_eq(skipped, normal, mode)

func test_shape_chain_retry_before_reward_popup_opens_in_four_modes() -> void:
	await _verify_reward_restarts(false)

func test_shape_chain_retry_with_selected_reward_in_four_modes() -> void:
	await _verify_reward_restarts(true)

func test_shape_chain_pause_delays_reward_until_resume_in_four_modes() -> void:
	watch_signals(UIManager)
	watch_signals(_host.board)
	watch_signals(_host.board.view)
	watch_signals(_host.board.director)
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			if not await _verify_shape_chain_pause(fast, low):
				return

func _verify_shape_chain_pause(fast: bool, low: bool) -> bool:
	var mode: String = "fast=%s low=%s" % [fast, low]
	await _host.load_case("shape_chain")
	_host.configure_modes(fast, low)
	_host.play_case()
	var normal_ready: bool = await wait_until(_shape_reward_settled, 8.0)
	assert_true(normal_ready, mode)
	if not normal_ready:
		return false
	assert_true(_host._sample_valid(_host.report), mode)
	_assert_shape_reward_matches_offer(mode)
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(_host.board.run))

	await _host.load_case("shape_chain")
	_host.configure_modes(fast, low)
	var board: Board = _host.board
	var director: PresentationDirector = board.director
	var matches_before: int = get_signal_emit_count(board.view, "match_visualized")
	var requests_before: int = get_signal_emit_count(board, "reward_requested")
	var opened_before: int = get_signal_emit_count(UIManager, "popup_opened")
	var pause_hits: Array[int] = []
	var pause_at_sweep: Callable = func(result: MatchResult, _cells: Array[Cell]) -> void:
		if result.cause == &"line_clear" and result.generation == 2:
			pause_hits.append(result.generation)
			_host.game.call("_toggle_pause")
	board.view.match_visualized.connect(pause_at_sweep)
	_host.play_case()
	var paused: bool = await wait_until(func() -> bool: return not pause_hits.is_empty() and get_tree().paused, 6.0)
	board.view.match_visualized.disconnect(pause_at_sweep)
	assert_true(paused, mode)
	if not paused:
		return false
	var steps_at_pause: int = get_signal_emit_count(director, "step_requested")
	assert_eq(get_signal_emit_count(board.view, "match_visualized") - matches_before, 3, mode)
	assert_eq(get_signal_emit_count(board, "reward_requested"), requests_before, mode)
	assert_eq(get_signal_emit_count(UIManager, "popup_opened"), opened_before, mode)
	assert_false(is_instance_valid(UIManager.current_popup) or board.can_selected, mode)
	var sweep: LineClearVisual = null
	for child: Node in board.view.get_children():
		if child is LineClearVisual:
			sweep = child as LineClearVisual
			break
	assert_not_null(sweep, mode)
	var progress: float = float(sweep.get("_progress")) if sweep != null else 0.0
	var paused_state: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	await get_tree().create_timer(0.4, true).timeout
	assert_true(is_instance_valid(sweep), mode)
	if is_instance_valid(sweep):
		assert_almost_eq(float(sweep.get("_progress")), progress, 0.00001, mode)
	assert_eq(get_signal_emit_count(director, "step_requested"), steps_at_pause, mode)
	assert_eq(get_signal_emit_count(board.view, "match_visualized") - matches_before, 3, mode)
	assert_eq(get_signal_emit_count(board, "reward_requested"), requests_before, mode)
	assert_eq(get_signal_emit_count(UIManager, "popup_opened"), opened_before, mode)
	assert_false(is_instance_valid(UIManager.current_popup) or board.can_selected, mode)
	assert_true(_host.report.is_empty(), mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), paused_state, mode)

	var hud: Hud = _host.game.get_node("UILayer/HUD") as Hud
	var opened_after_chain: Array[bool] = []
	var observe_open: Callable = func(popup: Control) -> void:
		if popup is PopupSkillChoice:
			opened_after_chain.append(get_signal_emit_count(board.view, "match_visualized") - matches_before == 6
				and not director.is_busy() and not board.view.is_presenting() and hud.displayed_score == 111)
	UIManager.popup_opened.connect(observe_open)
	_host.game.call("_toggle_pause")
	assert_false(get_tree().paused, mode)
	var resumed: bool = await wait_until(_shape_reward_settled, 8.0)
	assert_true(resumed, mode)
	if not resumed:
		UIManager.popup_opened.disconnect(observe_open)
		return false
	assert_true(_host._sample_valid(_host.report), mode)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	_assert_shape_reward_matches_offer(mode)
	assert_eq(board.run.state.pending_rewards, 1, mode)
	assert_eq(board.run.state.rewards.consumed_count, 0, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline, mode)
	await get_tree().create_timer(0.4, true).timeout
	UIManager.popup_opened.disconnect(observe_open)
	assert_eq(opened_after_chain, [true], mode)
	assert_same(UIManager.current_popup, popup, mode)
	assert_true(get_tree().paused and not board.can_selected, mode)
	assert_eq(get_signal_emit_count(board.view, "match_visualized") - matches_before, 6, mode)
	assert_eq(get_signal_emit_count(board, "reward_requested") - requests_before, 1, mode)
	assert_eq(get_signal_emit_count(UIManager, "popup_opened") - opened_before, 1, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline, mode)
	return true

func _shape_reward_settled() -> bool:
	return not _host.report.is_empty() and _reward_popup_ready()

func _assert_shape_reward_matches_offer(mode: String) -> void:
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	var offer: SkillOffer = _host.board.run.state.rewards.active_offer
	assert_not_null(offer, mode)
	if offer != null:
		_assert_popup_offer(popup, offer, mode)

func _verify_reward_restarts(opened: bool) -> void:
	# The acceptance fixture usually handles restart by reloading the same case.
	_host.game.set("use_external_restart", false)
	var flow: GameRewardFlow = _host.game.get("_reward_flow") as GameRewardFlow
	watch_signals(UIManager)
	watch_signals(flow)
	for fast: bool in [false, true]:
		for low: bool in [false, true]:
			if not await _verify_reward_restart(fast, low, opened, flow):
				return

func _verify_reward_restart(fast: bool, low: bool, opened: bool, flow: GameRewardFlow) -> bool:
	var mode: String = "fast=%s low=%s opened=%s" % [fast, low, opened]
	await _host.load_case("shape_chain")
	_host.configure_modes(fast, low)
	var old_run: RunController = _host.board.run
	var opened_before: int = get_signal_emit_count(UIManager, "popup_opened")
	var committed_before: int = get_signal_emit_count(flow, "selection_committed")
	var results: Array[bool] = []
	var pending: Array[PopupSkillChoice] = []
	var on_popup_inserted: Callable = func(child: Node) -> void:
		if child is PopupSkillChoice and pending.is_empty():
			var popup: PopupSkillChoice = child as PopupSkillChoice
			pending.append(popup)
			# The manager assigns current_popup after add_child, then awaits process_frame.
			_restart_at_reward.call_deferred(old_run, popup, false, flow, results, mode)
	if not opened:
		UIManager.child_entered_tree.connect(on_popup_inserted)
	_host.play_case()
	if opened:
		var ready: bool = await wait_until(_reward_popup_ready, 8.0)
		assert_true(ready, mode)
		if not ready:
			return false
		_restart_at_reward(old_run, UIManager.current_popup as PopupSkillChoice, true, flow, results, mode)
	var completed: bool = await wait_until(func() -> bool: return not results.is_empty(), 8.0)
	if not opened:
		UIManager.child_entered_tree.disconnect(on_popup_inserted)
	assert_true(completed, mode)
	if not completed:
		return false
	assert_eq(results, [true], mode)
	assert_eq(get_signal_emit_count(UIManager, "popup_opened") - opened_before, 1 if opened else 0, mode)
	assert_eq(get_signal_emit_count(flow, "selection_committed"), committed_before, mode)
	return results == [true]

func _restart_at_reward(old_run: RunController, popup: PopupSkillChoice, opened: bool, flow: GameRewardFlow, results: Array[bool], mode: String) -> void:
	if not is_instance_valid(_host):
		return
	var game: Node2D = _host.game
	var board: Board = _host.board
	assert_same(board.run, old_run, mode)
	if board.run != old_run:
		results.append(false)
		return
	assert_same(UIManager.current_popup, popup, mode)
	assert_eq(old_run.state.ledger.total, 111, mode)
	assert_eq(old_run.state.pending_rewards, 1, mode)
	assert_eq(old_run.state.rewards.consumed_count, 0, mode)
	assert_false(board.can_selected, mode)
	var offer: SkillOffer = old_run.state.rewards.active_offer
	assert_not_null(offer, mode)
	if offer == null or not is_instance_valid(popup):
		results.append(false)
		return
	var old_command: int = old_run.last_command_id
	var confirm: Callable
	var skill_id: StringName = &""
	if opened:
		assert_true(get_tree().paused, mode)
		var index: int = _first_available_choice(offer)
		assert_gte(index, 0, mode)
		if index < 0:
			results.append(false)
			return
		skill_id = offer.choices[index].skill_id
		(popup.options.get_child(index) as Button).pressed.emit()
		assert_false(popup.confirm_button.disabled, mode)
		confirm = _confirmation_callback(popup, flow)
		assert_true(confirm.is_valid(), mode)
	else:
		assert_null(popup.offer, mode)
		assert_false(get_tree().paused, mode)
		assert_true(popup.skill_selected.get_connections().is_empty(), mode)
	var replay_old: Callable = func() -> void:
		game.call("_on_reward_requested", old_run, offer)
		if confirm.is_valid(): confirm.call(offer.offer_id, skill_id)
	var director: PresentationDirector = board.director
	var during_spawn: Array[bool] = []
	var replay_on_spawn: Callable = func(step: PresentationStep, epoch: int, token: int) -> void:
		if step.kind != PresentationStep.Kind.SPAWN or not during_spawn.is_empty():
			return
		var current: RunController = board.run
		assert_ne(current.state.run_id, old_run.state.run_id, mode)
		assert_false(board.can_selected, mode)
		var before: String = RunSnapshot.digest(RunSnapshot.capture(current))
		replay_old.call()
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(current)), before, mode)
		during_spawn.append(director.is_current(epoch, token) and not board.can_selected and not get_tree().paused)
	director.step_requested.connect(replay_on_spawn)
	var restarted: bool = bool(await game.call("_on_retry_requested"))
	if is_instance_valid(director) and director.step_requested.is_connected(replay_on_spawn):
		director.step_requested.disconnect(replay_on_spawn)
	if not is_instance_valid(_host) or _host.game != game:
		return
	assert_true(restarted, mode)
	if not restarted:
		results.append(false)
		return
	assert_eq(during_spawn, [true], mode)
	var fresh: RunController = board.run
	var initial: String = RunSnapshot.digest(RunSnapshot.capture(fresh))
	replay_old.call()
	# The caller is already using the GUT awaiter to wait for this coroutine.
	for _frame: int in range(8):
		await get_tree().process_frame
		if not is_instance_valid(_host) or _host.game != game:
			return
	assert_false(is_instance_valid(popup), mode)
	assert_same(board.run, fresh, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(fresh)), initial, mode)
	assert_eq(old_run.last_command_id, old_command, mode)
	assert_eq(old_run.state.rewards.consumed_count, 0, mode)
	assert_eq(fresh.state.action_id, 0, mode)
	assert_eq(fresh.state.ledger.total, 0, mode)
	assert_eq((game.get_node("UILayer/HUD") as Hud).displayed_score, 0, mode)
	assert_eq(fresh.state.pending_rewards, 0, mode)
	assert_eq(fresh.state.rewards.consumed_count, 0, mode)
	assert_true(fresh.state.rewards.acquired.is_empty(), mode)
	assert_null(fresh.state.rewards.active_offer, mode)
	assert_false(is_instance_valid(UIManager.current_popup) or get_tree().paused, mode)
	assert_true(board.can_selected and not board.director.is_busy(), mode)
	var first: PieceState = board.rules.state.get_snapshot().front()
	await board._on_coordinate_pressed(first.coordinate)
	assert_not_null(board.selected_piece, mode)
	assert_same(board.selected_piece, board.view.get_piece(first.piece_id), mode)
	results.append(true)

func _play_and_choose(fast: bool, low: bool, skip_chain: bool, mode: String) -> Dictionary:
	await _host.load_case("shape_chain")
	_host.configure_modes(fast, low)
	var board: Board = _host.board
	var director: PresentationDirector = board.director
	var skipped: Array[int] = []
	var request_skip: Callable = func(step: PresentationStep, _epoch: int, _token: int) -> void:
		if step.kind == PresentationStep.Kind.MATCHES and not step.matches.is_empty() and step.matches.front().generation == 2:
			_host.game.call_deferred("_request_skip")
	var observe_skip: Callable = func(step: PresentationStep, _epoch: int, _token: int) -> void:
		assert_eq(step.kind, PresentationStep.Kind.MATCHES, mode)
		if not step.matches.is_empty():
			skipped.append(step.matches.front().generation)
	if skip_chain:
		director.step_requested.connect(request_skip)
		director.step_skip_requested.connect(observe_skip)
	_host.play_case()
	var arrived: bool = await wait_until(func() -> bool: return not _host.report.is_empty(), 8.0)
	if skip_chain:
		director.step_requested.disconnect(request_skip)
		director.step_skip_requested.disconnect(observe_skip)
	assert_true(arrived, mode)
	if not arrived:
		return {}
	if skip_chain:
		assert_eq(skipped, [2, 3, 4, 5], mode)
	else:
		assert_true(_host._sample_valid(_host.report), mode)
	assert_eq(int(_host.report.score), 111, mode)
	assert_eq((_host.game.get_node("UILayer/HUD") as Hud).displayed_score, 111, mode)
	var popup_ready: bool = await wait_until(_reward_popup_ready, 4.0)
	assert_true(popup_ready, mode)
	if not popup_ready:
		return {}
	assert_false(board.can_selected, mode)
	assert_true(get_tree().paused, mode)
	assert_false(director.is_busy() or director.skip_score_requested, mode)
	var active: RunController = board.run
	assert_eq(active.state.pending_rewards, 1, mode)
	assert_eq(active.state.rewards.consumed_count, 0, mode)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup, mode)
	var offer: SkillOffer = active.state.rewards.active_offer
	assert_not_null(offer, mode)
	if popup == null or offer == null:
		return {}
	assert_eq(offer.choices.size(), 3, mode)
	_assert_popup_offer(popup, offer, mode)
	var index: int = _first_available_choice(offer)
	assert_gte(index, 0, mode)
	if index < 0:
		return {}
	var skill_id: StringName = offer.choices[index].skill_id
	var frozen: String = RunSnapshot.digest(RunSnapshot.capture(active))
	var unavailable: Dictionary[StringName, String] = offer.unavailable.duplicate()
	(popup.options.get_child(index) as Button).pressed.emit()
	assert_false(popup.confirm_button.disabled, mode)
	var confirmation: String = popup.confirm_button.text
	_host.game.call("_request_skip")
	assert_same(UIManager.current_popup, popup, mode)
	if not is_instance_valid(popup) or UIManager.current_popup != popup:
		return {}
	assert_same(active.state.rewards.active_offer, offer, mode)
	assert_false(popup.confirm_button.disabled, mode)
	assert_eq(popup.confirm_button.text, confirmation, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(active)), frozen, mode)
	assert_eq(offer.unavailable, unavailable, mode)
	assert_true(get_tree().paused, mode)
	assert_false(board.can_selected or director.skip_score_requested, mode)
	_assert_popup_offer(popup, offer, mode)
	var completed: String = await _confirm_once(board, active, popup, skill_id, mode)
	return {"frozen": frozen, "completed": completed, "skill_id": skill_id} if not completed.is_empty() else {}

func _reward_popup_ready() -> bool:
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	return is_instance_valid(popup) and popup.offer != null and not popup.skill_selected.get_connections().is_empty()

func _assert_popup_offer(popup: PopupSkillChoice, expected: SkillOffer, mode: String) -> void:
	assert_eq(RunSnapshot.offer_data(popup.offer), RunSnapshot.offer_data(expected), mode)
	assert_not_null(popup.offer, mode)
	if popup.offer == null:
		return
	assert_eq(popup.offer.unavailable, expected.unavailable, mode)
	for index: int in range(expected.choices.size()):
		var skill: SkillDefinition = expected.choices[index]
		var card: SkillCard = popup.options.get_child(index) as SkillCard
		assert_not_null(card, mode)
		if card == null:
			continue
		assert_same(card.get("_skill"), skill, mode)
		assert_eq(card.disabled, expected.unavailable.has(skill.skill_id), mode)
		var target: SkillTarget = card.get("_target") as SkillTarget
		assert_not_null(target, mode)
		if target != null:
			assert_eq(RunSnapshot.target_data(target), RunSnapshot.target_data(expected.targets[skill.skill_id]), mode)

func _confirm_once(board: Board, active: RunController, popup: PopupSkillChoice, skill_id: StringName, mode: String) -> String:
	var flow: GameRewardFlow = _host.game.get("_reward_flow") as GameRewardFlow
	var original_callback: Callable = _confirmation_callback(popup, flow)
	assert_true(original_callback.is_valid(), mode)
	if not original_callback.is_valid():
		return ""
	var commits: Array[int] = []
	var observe_commit: Callable = func(run: RunController) -> void: commits.append(run.state.rewards.consumed_count)
	flow.selection_committed.connect(observe_commit)
	var offer_id: int = popup.offer.offer_id
	var previous_command: int = active.last_command_id
	var expected_acquired: Dictionary[StringName, int] = active.state.rewards.acquired.duplicate()
	expected_acquired[skill_id] = expected_acquired.get(skill_id, 0) + 1
	popup.confirm_button.pressed.emit()
	var finished: bool = await wait_until(func() -> bool:
		return board.can_selected and not is_instance_valid(UIManager.current_popup), 8.0)
	assert_true(finished, mode)
	if not finished:
		flow.selection_committed.disconnect(observe_commit)
		return ""
	var final: String = RunSnapshot.digest(RunSnapshot.capture(active))
	# Re-deliver the old popup callback after the actual reward has settled.
	original_callback.call(offer_id, skill_id)
	_host.game.call("request_rewards")
	await wait_process_frames(8)
	flow.selection_committed.disconnect(observe_commit)
	assert_eq(commits, [1], mode)
	assert_same(board.run, active, mode)
	assert_eq(active.last_command_id, previous_command + 1, mode)
	assert_eq(active.state.rewards.consumed_count, 1, mode)
	assert_eq(active.state.rewards.acquired, expected_acquired, mode)
	assert_eq(active.state.pending_rewards, 0, mode)
	assert_null(active.state.rewards.active_offer, mode)
	assert_false(is_instance_valid(UIManager.current_popup) or get_tree().paused, mode)
	assert_true(board.can_selected and not board.director.is_busy(), mode)
	assert_false(board.director.skip_score_requested, mode)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(active)), final, mode)
	return final

func _confirmation_callback(popup: PopupSkillChoice, flow: GameRewardFlow) -> Callable:
	for connection: Dictionary in popup.skill_selected.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() == flow and callback.get_method() == &"_choose":
			return callback
	return Callable()

func _first_available_choice(offer: SkillOffer) -> int:
	for index: int in range(offer.choices.size()):
		var choice: SkillDefinition = offer.choices[index]
		var target: SkillTarget = offer.targets[choice.skill_id]
		if not offer.unavailable.has(choice.skill_id) and not choice.requires_color_choice(target.level_before):
			return index
	return -1
