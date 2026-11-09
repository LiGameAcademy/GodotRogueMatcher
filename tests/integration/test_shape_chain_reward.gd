extends GutTest

## Checks that skipping a shape chain preserves its frozen reward and commits a choice once.
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
	var original_callback: Callable
	for connection: Dictionary in popup.skill_selected.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() == flow and callback.get_method() == &"_choose":
			original_callback = callback
			break
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

func _first_available_choice(offer: SkillOffer) -> int:
	for index: int in range(offer.choices.size()):
		var choice: SkillDefinition = offer.choices[index]
		var target: SkillTarget = offer.targets[choice.skill_id]
		if not offer.unavailable.has(choice.skill_id) and not choice.requires_color_choice(target.level_before):
			return index
	return -1
