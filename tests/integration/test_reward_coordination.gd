extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var game: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	LevelUpSystem.is_resolving = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	game = main.get_node("Game") as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	board = game.get_node("Board") as Board
	board.game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	board.run.state.pending_rewards = 2
	board.run.enter_rewards()
	board.can_selected = false
	_install_offer()

func after_each() -> void:
	UIManager.close_popup()
	get_tree().paused = false
	if is_instance_valid(main): main.queue_free()
	await wait_process_frames(3)

func _install_offer() -> void:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = board.run.state.rewards.next_offer_id
	offer.reward_id = board.run.state.rewards.consumed_count + 1
	for id: StringName in [&"score_multiplier", &"core_drop"]:
		for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
			if skill.skill_id == id:
				offer.choices.append(skill)
				offer.targets[id] = SkillRules.freeze_target(board.run.state, skill)
	board.run.state.rewards.next_offer_id += 1
	board.run.state.rewards.active_offer = offer

func _open() -> PopupSkillChoice:
	BoardRunFlow.continue_run(board, board.run)
	await wait_process_frames(6)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	return popup

func test_closing_keeps_reward_without_automatic_reopen_and_board_remains_locked() -> void:
	var popup: PopupSkillChoice = await _open()
	if popup == null: return
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	UIManager.close_popup()
	await wait_process_frames(6)
	assert_false(is_instance_valid(UIManager.current_popup), "普通关闭不能循环重弹")
	assert_eq(board.run.state.pending_rewards, 2)
	assert_eq(board.run.state.rewards.consumed_count, 0)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
	assert_false(board.can_selected)
	assert_true(game.has_method("request_rewards"), "Game提供恢复选卡入口")

func test_popup_cannot_mutate_authoritative_frozen_targets() -> void:
	var popup: PopupSkillChoice = await _open()
	if popup == null: return
	var original: SkillOffer = board.run.state.rewards.active_offer
	var coordinate: Vector2i = original.targets[&"core_drop"].coordinate
	assert_ne(popup.offer, original)
	popup.offer.targets[&"core_drop"].coordinate = Vector2i(-1, -1)
	assert_eq(original.targets[&"core_drop"].coordinate, coordinate)

func test_same_run_old_popup_callback_does_not_submit_again() -> void:
	var popup: PopupSkillChoice = await _open()
	if popup == null: return
	var connections: Array[Dictionary] = []
	connections.assign(popup.skill_selected.get_connections())
	assert_eq(connections.size(), 1)
	if connections.size() != 1: return
	var old_callback: Callable = connections[0].callable
	var old_offer_id: int = popup.offer.offer_id
	popup._select(0)
	popup.confirm_selection()
	await board.finish_presentation()
	await wait_process_frames(8)
	var command_id: int = board.run.last_command_id
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	old_callback.call(old_offer_id, &"score_multiplier")
	assert_eq(board.run.last_command_id, command_id, "旧面板不补取当前奖励身份提交新命令")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)

func test_rule_waiting_blocks_move_without_global_pause() -> void:
	var run: RunController = board.run
	var offer: SkillOffer = run.prepare_offer()
	var piece: PieceState = run.state.rules.place_piece(Vector2i(8, 8), 0)
	get_tree().paused = false
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = piece.piece_id
	command.target = Vector2i(8, 7)
	assert_false(run.execute_command(command).accepted)
	assert_same(run.advance().offer, offer)
	assert_eq(run.state.pending_rewards, 2)
