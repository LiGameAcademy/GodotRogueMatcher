extends GutTest

const MAIN: PackedScene = preload("res://main.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	(main.get_node("Game/Board") as Board).game_mode = GameModes.CLASSIC
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	for piece: PieceState in board.rules.state.get_snapshot(): board.remove_piece(piece.coordinate)
	LevelUpSystem.reset_system()

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_match_finishes_before_score_notification_and_reward_popup() -> void:
	GameManager.add_score(50)
	for x: int in range(5): _place(Vector2i(x, 0), 0)
	watch_signals(GameManager)
	board.present_matches(board.run.resolve_all_matches())
	LevelUpSystem.resolve_pending_rewards(board)
	assert_true(board.view.is_presenting())
	assert_eq(GameManager.score, 100)
	# 奖励权利在规则结算时已排队，只有面板展示等待演出。
	assert_eq(LevelUpSystem.pending_rewards, 1)
	assert_signal_not_emitted(GameManager, "score_changed")
	assert_false(get_tree().paused)
	assert_false(is_instance_valid(UIManager.current_popup))
	await board.view.wait_for_presentation()
	assert_false(is_instance_valid(UIManager.current_popup))
	assert_lt((main.get_node("Game/UILayer/HUD") as Hud).displayed_score, 100)
	await board.finish_presentation()
	await wait_process_frames(3)
	assert_signal_emitted_with_parameters(GameManager, "score_changed", [100])
	assert_eq(LevelUpSystem.pending_rewards, 1)
	assert_true(UIManager.current_popup is PopupSkillChoice)
	assert_false(board.view.is_presenting())
	(UIManager.current_popup as PopupSkillChoice)._select(0)
	await wait_process_frames(3)

func test_blast_waits_for_longer_visual_before_reward_pauses_game() -> void:
	assert_true(board.load_explosion_demo())
	GameManager.add_score(30)
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	board.move_selected_piece(board.get_cell(Vector2i(5, 4)), 0.01)
	await get_tree().create_timer(0.3).timeout
	assert_eq(GameManager.score, 100)
	assert_true(board.view.is_presenting())
	assert_false(get_tree().paused)
	assert_false(is_instance_valid(UIManager.current_popup))
	await board.finish_presentation()
	await wait_process_frames(3)
	assert_true(UIManager.current_popup is PopupSkillChoice)
	assert_false(board.view.is_presenting())
	(UIManager.current_popup as PopupSkillChoice)._select(0)
	await wait_process_frames(3)

func test_core_selection_match_completes_before_next_queued_reward() -> void:
	for x: int in range(4): _place(Vector2i(x, 0), 1)
	GameManager.add_score(260)
	LevelUpSystem.resolve_pending_rewards(board)
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	popup.offer.targets[&"core_drop"].coordinate = Vector2i(4, 0)
	for index: int in range(popup.offer.choices.size()):
		if popup.offer.choices[index].skill_id == &"core_drop":
			popup._select(index)
			break
	assert_true(board.view.is_presenting())
	assert_false(get_tree().paused)
	await wait_process_frames(3)
	assert_false(is_instance_valid(UIManager.current_popup) and UIManager.current_popup.visible)
	await board.finish_presentation()
	await wait_process_frames(3)
	var next: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(next)
	assert_eq(next.offer.reward_id, 2)
	assert_eq(GameManager.score, 310)
	assert_false(board.view.is_presenting())
	next._select(0)
	await wait_process_frames(3)

func _place(coordinate: Vector2i, color: int) -> void:
	var piece: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	piece.piece_type = color
	board.place_piece(coordinate, piece)

func test_retry_cancels_wait_without_publishing_old_score_or_opening_reward() -> void:
	GameManager.add_score(50)
	for x: int in range(5): _place(Vector2i(x, 0), 0)
	board.present_matches(board.run.resolve_all_matches())
	LevelUpSystem.resolve_pending_rewards(board)
	assert_true(board.view.is_presenting())
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	assert_eq(GameManager.score, 0)
	assert_eq(LevelUpSystem.pending_rewards, 0)
	assert_false(LevelUpSystem.is_resolving)
	assert_false(board.view.is_presenting())
	assert_false(is_instance_valid(UIManager.current_popup))
	assert_true(board.can_selected)
