class_name GameRewardFlow
extends RefCounted

## Game持有的选卡协调器；只提交命令、展示结果，不拥有奖励权利。
signal resume_available(waiting: bool)
signal selection_committed(active: RunController)
signal error_reported(reason: String)

var _board: Board
var _run: RunController
var _popup: PopupSkillChoice
var _epoch: int = 0
var _offer_id: int = 0
var _reward_id: int = 0
var _opening: bool = false
var _suspended: bool = false
var _previous_pause: bool = false
var _owns_pause: bool = false
var _tree: SceneTree

func present(board: Board, active: RunController, offer: SkillOffer, resume: bool = false) -> void:
	if board.run != active or offer == null or active.state.is_game_over or not active.state.rule_error.is_empty(): return
	if _run == active and _offer_id == offer.offer_id:
		if _opening or is_instance_valid(_popup) or (_suspended and not resume): return
	cancel()
	_board = board
	_run = active
	_offer_id = offer.offer_id
	_reward_id = offer.reward_id
	_opening = true
	var epoch: int = _epoch
	var finished: bool = await board.finish_presentation()
	if not _valid(epoch): return
	if not finished:
		cancel()
		error_reported.emit("reward_presentation_failed")
		return
	board.cancel_buffered_input("reward_popup")
	board.can_selected = false
	_previous_pause = board.get_tree().paused
	var popup: PopupSkillChoice = await UIManager.open_popup("popup_skill_choice", {"offer": offer.snapshot()}) as PopupSkillChoice
	if not _valid(epoch):
		if is_instance_valid(popup) and UIManager.current_popup == popup: popup.close_view()
		return
	_opening = false
	if not is_instance_valid(popup):
		_suspended = true
		resume_available.emit(true)
		return
	_popup = popup
	_tree = board.get_tree()
	_owns_pause = true
	_tree.paused = true
	popup.skill_selected.connect(_choose.bind(epoch, active, offer.reward_id))
	popup.color_skill_selected.connect(_choose_color.bind(epoch, active, offer.reward_id))
	popup.closed.connect(_closed.bind(epoch))
	popup.tree_exiting.connect(_closed.bind(epoch))
	if active.recorder != null: active.recorder.set_interval("choice")
	board.observation.present_offer(offer)
	board.feedback_requested.emit(&"reward")
	resume_available.emit(false)

func cancel() -> void:
	_epoch += 1
	_release_pause()
	if is_instance_valid(_popup) and UIManager.current_popup == _popup: _popup.close_view()
	_popup = null
	_run = null
	_board = null
	_offer_id = 0
	_reward_id = 0
	_opening = false
	_suspended = false
	resume_available.emit(false)

func _choose_color(offer_id: int, skill_id: StringName, color: int, epoch: int, active: RunController, reward_id: int) -> void:
	_choose(offer_id, skill_id, epoch, active, reward_id, color)

func _choose(offer_id: int, skill_id: StringName, epoch: int, active: RunController, reward_id: int, color: int = -1) -> void:
	if not _valid(epoch) or _run != active or offer_id != _offer_id or reward_id != _reward_id or not is_instance_valid(_popup): return
	if UIManager.current_popup != _popup: return
	_board.observation.selecting_skill()
	var input_id: String = _board.observation.input("choose_skill")
	var command: ChooseSkillCommand = ChooseSkillCommand.new(active.state.run_id, active.last_command_id + 1, active.state.action_id)
	command.reward_id = reward_id
	command.offer_id = offer_id
	command.skill_id = skill_id
	command.selected_color = color
	var outcome: CommandResult = active.execute_command(command)
	_board.observation.resolve(input_id, "submitted" if outcome.accepted else "rejected", outcome.reason, str(command.command_id))
	if not outcome.accepted:
		if outcome.rule_error:
			var reason: String = outcome.reason
			cancel()
			error_reported.emit(reason)
		elif outcome.offer != null and outcome.offer.offer_id != offer_id:
			present(_board, active, outcome.offer, true)
		else:
			if active.state.rewards.active_offer != null: _popup.set_unavailable(active.state.rewards.active_offer.unavailable)
			_popup.show_error(outcome.reason)
		return
	var popup: PopupSkillChoice = _popup
	var board: Board = _board
	_epoch += 1
	_popup = null
	_offer_id = 0
	_release_pause()
	board.present_skill_result(outcome.skill)
	popup.accept_selection(true)
	selection_committed.emit(active)

func _closed(epoch: int) -> void:
	if not _valid(epoch): return
	_epoch += 1
	_release_pause()
	_popup = null
	_opening = false
	_suspended = true
	resume_available.emit(true)

func _release_pause() -> void:
	# Game退出时Board可能已离树；仍须释放本协调器取得的暂停。
	if _owns_pause and is_instance_valid(_tree): _tree.paused = _previous_pause
	_owns_pause = false
	_tree = null

func _valid(epoch: int) -> bool:
	return epoch == _epoch and is_instance_valid(_board) and _run != null and _board.run == _run
