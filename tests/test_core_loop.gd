extends GutTest

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const PIECE_SCENE: PackedScene = preload("res://gameplay/board/piece/chess_piece.tscn")
var main: Node2D
var board: Board

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	main = MAIN_SCENE.instantiate() as Node2D
	main.get_node("Game").set("persist_preferences", false)
	(main.get_node("Game/Board") as Board).game_mode = GameModes.CLASSIC
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(main)
	board = main.get_node("Game/Board") as Board
	await board.initialized
	_clear_board()

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_occupied_start_can_move_and_restores_obstacle() -> void:
	_place(Vector2i(0, 0), 0)
	var result: BoardMoveResult = board.rules.validate_move(board.rules.state.get_piece_id(Vector2i.ZERO), Vector2i(2, 0))
	assert_eq(result.path.size(), 3)
	assert_ne(board.rules.state.get_piece_id(Vector2i.ZERO), 0)
	assert_false(board.rules.validate_move(result.piece_id, Vector2i.ZERO).is_valid())

func test_compatibility_writes_refresh_special_tooltips_at_rest() -> void:
	var display: ChessPiece = _place(Vector2i.ZERO, 0)
	assert_true(board.run.abilities.assign_fuse(display.piece_id))
	board.refresh_ability_markers()
	assert_string_contains(display.tooltip_region.tooltip_text, "花生")
	assert_true(board.set_piece_color(Vector2i.ZERO, 3))
	assert_string_contains(display.tooltip_region.tooltip_text, "核桃")
	assert_false(display.tooltip_region.tooltip_text.contains("花生"))
	var ghost: ChessPiece = PIECE_SCENE.instantiate() as ChessPiece
	ghost.is_ghost = true
	assert_true(board.place_piece(Vector2i(1, 0), ghost))
	assert_string_contains(ghost.tooltip_region.tooltip_text, "幽灵棋子")
	assert_eq(GameManager.turn_count, 1)
	assert_eq(GameManager.score, 0)

func test_click_move_advances_one_turn_and_spawns_three() -> void:
	var piece: ChessPiece = _place(Vector2i.ZERO, 0)
	board._on_cell_pressed(board.get_cell(Vector2i.ZERO))
	await board._on_cell_pressed(board.get_cell(Vector2i(2, 0)))
	assert_eq(board.get_cell(Vector2i(2, 0)).piece, piece)
	assert_ne(board.get_cell(Vector2i.ZERO).piece, piece)
	assert_eq(GameManager.turn_count, 2)
	assert_eq(GameManager.piece_count, 4)
	assert_true(board.can_selected)

func test_blocked_move_preserves_turn_score_and_occupancy() -> void:
	var piece: ChessPiece = _place(Vector2i.ZERO, 0)
	_place(Vector2i(1, 0), 1)
	_place(Vector2i(0, 1), 2)
	board.selected_piece = piece
	assert_false(await board.move_selected_piece(board.get_cell(Vector2i(2, 2)), 0.01))
	assert_eq(board.get_cell(Vector2i.ZERO).piece, piece)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(GameManager.score, 0)
	assert_eq(GameManager.piece_count, 3)
	assert_true(board.can_selected)

func test_five_match_scores_and_clears_without_stale_references() -> void:
	for x: int in range(4):
		_place(Vector2i(x, 0), 0)
	var piece: ChessPiece = _place(Vector2i(4, 1), 0)
	_place(Vector2i(8, 8), 1)
	board.selected_piece = piece
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.01))
	await wait_process_frames(2)
	assert_eq(GameManager.score, 50)
	assert_eq(GameManager.piece_count, 1)
	assert_eq(board.get_empty_cells().size(), 80)
	assert_true(board.can_selected)

func test_partial_spawn_fills_last_empty_cell_and_ends_once() -> void:
	_fill_without_lines()
	_remove(Vector2i(8, 8))
	assert_false(GameManager.is_game_over)
	var previous_births: int = board.run.state.spawn_history.size()
	await _resume_refill()
	assert_eq(board.run.state.spawn_history.size() - previous_births, 1)
	assert_true(GameManager.is_game_over)
	assert_eq(board.get_empty_cells().size(), 0)
	await wait_process_frames(3)
	assert_true(is_instance_valid(UIManager.current_popup))
	assert_true(UIManager.current_popup.has_signal("retry_requested"))

func test_spawn_checks_match_before_full_board_failure() -> void:
	_fill_without_lines()
	_remove(Vector2i(8, 8))
	# 内容已由独立随机流锁入预告，按真实下一枚颜色构造最后空位五连。
	var next_color: int = board.run.state.spawning.preview(1)[0].color
	for n: int in range(4):
		board.set_piece_color(Vector2i(4 + n, 8), next_color)
	var previous_births: int = board.run.state.spawn_history.size()
	await _resume_refill()
	assert_eq(board.run.state.spawn_history.size() - previous_births, 3)
	assert_false(GameManager.is_game_over)
	assert_gt(GameManager.score, 0)
	assert_gt(board.get_empty_cells().size(), 0)

func test_crossed_lines_deduplicate() -> void:
	for n: int in range(5):
		_place(Vector2i(n, 2), 0)
		if n != 2:
			_place(Vector2i(2, n), 0)
	assert_eq(MatchSystem.check_for_elimination(board, board.get_cell(Vector2i(2, 2))).size(), 9)

func test_four_does_not_match_and_diagonal_five_does() -> void:
	for n: int in range(4):
		_place(Vector2i(n, n), 2)
	assert_eq(MatchSystem.check_for_elimination(board, board.get_cell(Vector2i(3, 3))).size(), 0)
	_place(Vector2i(4, 4), 2)
	assert_eq(MatchSystem.check_for_elimination(board, board.get_cell(Vector2i(4, 4))).size(), 5)

func test_full_clear_repopulates_and_returns_to_input() -> void:
	for x: int in range(4):
		_place(Vector2i(x, 0), 0)
	board.selected_piece = _place(Vector2i(4, 1), 0)
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.01))
	assert_eq(GameManager.score, 50)
	assert_eq(GameManager.piece_count, 3)
	assert_eq(GameManager.turn_count, 2)
	assert_true(board.can_selected)

func test_failed_spawn_does_not_offer_pending_rescue_reward() -> void:
	_fill_without_lines()
	GameManager.add_score(100)
	board.run.check_space_after_spawning()
	await board.resume_run(board.run)
	await main.get_node("Game").call("request_rewards")
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	assert_true(GameManager.is_game_over)
	assert_false(UIManager.current_popup is PopupSkillChoice)
	assert_eq(LevelUpSystem.pending_rewards, 1)

func test_candidate_ids_are_distinct() -> void:
	for attempt: int in range(20):
		var local: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), attempt)
		local.state.pending_rewards = 1
		var offer: SkillOffer = local.prepare_offer()
		assert_eq(offer.choices.size(), 3)
		assert_ne(offer.choices[0].skill_id, offer.choices[1].skill_id)
		assert_ne(offer.choices[0].skill_id, offer.choices[2].skill_id)
		assert_ne(offer.choices[1].skill_id, offer.choices[2].skill_id)
func test_reward_filling_last_space_ends_before_next_reward() -> void:
	_fill_without_lines()
	_remove(Vector2i(8, 8))
	GameManager.add_score(260)
	main.get_node("Game").call("request_rewards")
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	_use_core_candidate(popup)
	popup._select(_skill_index(popup, &"core_drop"))
	popup.confirm_selection()
	await get_tree().create_timer(0.85).timeout
	assert_true(GameManager.is_game_over)
	assert_eq(board.get_empty_cells().size(), 0)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(LevelUpSystem.pending_rewards, 1)
	assert_false(board.can_selected)
	assert_false(UIManager.current_popup is PopupSkillChoice)

func test_retry_clears_score_obstacles_and_upgrade_state() -> void:
	_fill_without_lines()
	GameManager.add_score(123)
	board.run.state.pending_rewards = 2
	GameManager.finish_game()
	await (main.get_node("Game/UILayer/HUD") as Hud).wait_for_score()
	await wait_process_frames(3)
	UIManager.current_popup.retry_requested.emit()
	await board.initialized
	assert_eq(GameManager.score, 0)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(GameManager.piece_count, 5)
	assert_eq(LevelUpSystem.pending_rewards, 0)
	assert_eq(LevelUpSystem.current_level, 0)
	assert_false(GameManager.is_game_over)
	assert_true(board.can_selected)
	for cell: Cell in board.get_empty_cells():
		assert_eq(board.rules.state.get_piece_id(cell.coordinate), 0)

func test_rewards_queue_and_selection_applies_once() -> void:
	GameManager.add_score(260)
	assert_eq(LevelUpSystem.pending_rewards, 2)
	assert_false(is_instance_valid(UIManager.current_popup))
	main.get_node("Game").call("request_rewards")
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	_use_core_candidate(popup)
	var index: int = _skill_index(popup, &"core_drop")
	popup._select(index)
	popup.confirm_selection()
	popup._select(index)
	popup.confirm_selection()
	assert_true(await board.director.wait_until_idle())
	await wait_process_frames(3)
	assert_eq(board.rules.state.get_piece_count(), 1)
	assert_eq(board.run.state.rewards.consumed_count, 1)
	var second: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_eq(second.offer.reward_id, 2)
	_use_score_candidate(second)
	second._select(_skill_index(second, &"score_multiplier"))
	second.confirm_selection()
	await wait_process_frames(3)
	assert_eq(board.run.state.explosion.multiplier_level, 1)
	assert_eq(board.run.state.rewards.consumed_count, 2)
	assert_eq(GameManager.piece_count, 1)
	assert_eq(LevelUpSystem.pending_rewards, 0)
	assert_false(is_instance_valid(UIManager.current_popup))
	assert_false(get_tree().paused)

func _skill_index(popup: PopupSkillChoice, id: StringName) -> int:
	for index: int in range(popup.offer.choices.size()):
		if popup.offer.choices[index].skill_id == id: return index
	fail_test("Missing expected skill: " + String(id))
	return 0

func test_f7_uses_real_reward_popup_and_returns_to_same_turn() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F7
	main.get_node("Game")._unhandled_key_input(key)
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	assert_true(get_tree().paused)
	assert_false(board.can_selected)
	assert_eq(LevelUpSystem.pending_rewards, 1)
	_use_core_candidate(popup)
	popup._select(_skill_index(popup, &"core_drop"))
	popup.confirm_selection()
	assert_true(await board.director.wait_until_idle())
	await wait_process_frames(3)
	assert_false(get_tree().paused)
	assert_true(board.can_selected)
	assert_eq(board.run.state.phase, RunState.Phase.INPUT)
	assert_eq(board.run.state.turn_count, 1)
	assert_eq(board.run.state.rewards.applications.size(), 1)
	assert_eq(board.run.state.rewards.applications[0].skill_id, &"core_drop")

func test_partial_invalid_core_target_keeps_offer_without_consuming_reward() -> void:
	GameManager.add_score(100)
	main.get_node("Game").call("request_rewards")
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	_use_core_candidate(popup)
	var previous: int = popup.offer.offer_id
	_place(popup.offer.targets[&"core_drop"].coordinate, 0)
	popup._select(_skill_index(popup, &"core_drop"))
	popup.confirm_selection()
	assert_eq(LevelUpSystem.pending_rewards, 1)
	assert_eq(board.run.state.rewards.consumed_count, 0)
	assert_eq(popup.offer.offer_id, previous)
	assert_eq(board.run.state.rules.state.get_piece_count(), 1)
	_use_score_candidate(popup)
	popup._select(_skill_index(popup, &"score_multiplier"))
	popup.confirm_selection()
	await wait_process_frames(3)
	assert_eq(LevelUpSystem.pending_rewards, 0)
	assert_eq(board.run.state.explosion.multiplier_level, 1)

func test_old_skill_callback_after_retry_cannot_modify_new_run() -> void:
	GameManager.add_score(100)
	main.get_node("Game").call("request_rewards")
	await (main.get_node('Game/UILayer/HUD') as Hud).wait_for_score()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	var old_id: int = popup.offer.offer_id
	var old_callback: Callable = popup.skill_selected.get_connections()[0].callable
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	old_callback.call(old_id, &"core_drop")
	assert_eq(board.run.state.rules.state.get_piece_count(), 5)
	assert_eq(board.run.state.rewards.consumed_count, 0)
	assert_false(board.run.state.explosion.unlocked)
	assert_false(is_instance_valid(UIManager.current_popup))
	await wait_process_frames(2)

func test_game_display_rebuild_does_not_reapply_item_or_reset_rule_ids() -> void:
	var item: ItemData = ItemRegistry.new().create_prism_tower()
	var display: ChessPiece = PIECE_SCENE.instantiate() as ChessPiece
	display.initialize_item(item)
	assert_true(board.place_piece(Vector2i.ZERO, display))
	var before: PieceState = board.rules.state.get_piece_at(Vector2i.ZERO)
	var previous_display: ChessPiece = board.get_cell(Vector2i.ZERO).piece
	assert_true(board.rebuild_view())
	assert_eq(board.rules.state.get_piece_at(Vector2i.ZERO).piece_id, before.piece_id)
	assert_ne(board.get_cell(Vector2i.ZERO).piece, previous_display)
	assert_eq(board.get_cell(Vector2i.ZERO).piece.item_data, item)
	assert_eq(board.view.get_piece(before.piece_id).piece_id, before.piece_id)
	assert_eq(GameManager.piece_count, 1)

func test_coordinator_rejects_rebuild_during_move_and_finishes_once() -> void:
	for x: int in range(4):
		_place(Vector2i(x, 0), 0)
	board.selected_piece = _place(Vector2i(4, 1), 0)
	_place(Vector2i(8, 8), 1)
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.1)
	assert_false(board.rebuild_view())
	await GameManager.turn_started
	await wait_process_frames(1)
	assert_eq(GameManager.score, 50)
	assert_eq(GameManager.turn_count, 2)
	assert_eq(board.rules.state.get_piece_count(), 1)
	assert_true(board.can_selected)

func test_retry_cancels_old_move_without_advancing_new_turn() -> void:
	board.selected_piece = _place(Vector2i.ZERO, 0)
	var previous_rules: BoardRules = board.rules
	board.move_selected_piece(board.get_cell(Vector2i(2, 0)), 0.5)
	main.get_node("Game")._on_retry_requested()
	await board.initialized
	assert_ne(board.rules, previous_rules)
	assert_eq(GameManager.score, 0)
	assert_eq(GameManager.turn_count, 1)
	assert_eq(board.rules.state.get_piece_count(), 5)
	assert_true(board.can_selected)

func test_extra_score_does_not_exempt_ordinary_spawn() -> void:
	board.selected_piece = _place(Vector2i.ZERO, 0)
	var award: Callable = func(_turn: int) -> void: GameManager.add_score(1)
	GameManager.turn_ended.connect(award, CONNECT_ONE_SHOT)
	assert_true(await board.move_selected_piece(board.get_cell(Vector2i(2, 0)), 0.01))
	assert_eq(GameManager.score, 1)
	assert_eq(board.rules.state.get_piece_count(), 4)
	assert_eq(GameManager.ledger.get_entries()[0].extra_score, 1)

func test_score_reset_notifies_display_and_replaces_ledger() -> void:
	GameManager.add_score(12)
	var previous: ScoreLedger = GameManager.ledger
	watch_signals(GameManager)
	GameManager.reset_game()
	assert_signal_emitted_with_parameters(GameManager, "score_changed", [0])
	assert_eq(GameManager.score, 0)
	assert_eq(GameManager.ledger.get_entries().size(), 0)
	assert_ne(GameManager.ledger, previous)
	assert_eq(previous.total, 12)

func test_move_rules_are_committed_while_animation_is_pending() -> void:
	for x: int in range(4):
		_place(Vector2i(x, 0), 0)
	board.selected_piece = _place(Vector2i(4, 1), 0)
	_place(Vector2i(8, 8), 1)
	board.move_selected_piece(board.get_cell(Vector2i(4, 0)), 0.2)
	assert_eq(GameManager.score, 50)
	assert_eq(board.rules.state.get_piece_count(), 1)
	assert_eq(board.run.state.phase, RunState.Phase.MOVING)
	assert_false(board.can_selected)
	await GameManager.turn_started
	await wait_process_frames(1)
	assert_eq(GameManager.score, 50)
	assert_eq(GameManager.turn_count, 2)
	assert_true(board.can_selected)

func test_presenting_committed_result_twice_does_not_repeat_effects() -> void:
	for x: int in range(5):
		_place(Vector2i(x, 0), 0)
	var results: Array[MatchResult] = board.run.resolve_all_matches()
	watch_signals(MatchSystem)
	watch_signals(board.view)
	board.present_matches(results)
	board.present_matches(results)
	assert_eq(GameManager.score, 50)
	assert_true(await board.finish_presentation())
	assert_signal_emit_count(MatchSystem, "match_made", 0)
	assert_signal_emit_count(board.view, "match_visualized", 1)
	assert_eq(GameManager.ledger.get_entries().size(), 1)

func test_fast_and_slow_move_playback_have_identical_rule_results() -> void:
	for duration: float in [0.01, 0.1]:
		_clear_board()
		for x: int in range(4):
			_place(Vector2i(x, 0), 0)
		board.selected_piece = _place(Vector2i(4, 1), 0)
		_place(Vector2i(8, 8), 1)
		assert_true(await board.move_selected_piece(board.get_cell(Vector2i(4, 0)), duration))
		assert_eq(GameManager.score, 50)
		assert_eq(GameManager.turn_count, 2)
		assert_eq(board.rules.state.get_piece_count(), 1)
		assert_eq(GameManager.ledger.get_entries().size(), 1)

func _clear_board() -> void:
	board.selected_piece = null
	for child: Node in board.view.get_cells():
		if child is Cell:
			_remove((child as Cell).coordinate)
	GameManager.reset_game()
	board._presented_events.clear()
	GameManager.start_turn()
	board.can_selected = true

func _place(coord: Vector2i, color: int) -> ChessPiece:
	var piece: ChessPiece = PIECE_SCENE.instantiate() as ChessPiece
	piece.piece_type = color
	assert_true(board.place_piece(coord, piece))
	return piece

func _remove(coord: Vector2i) -> void:
	board.remove_piece(coord)

func _fill_without_lines() -> void:
	for x: int in range(board.cols):
		for y: int in range(board.rows):
			_place(Vector2i(x, y), (x + 2 * y) % 5)

## 交互验收使用受控候选；候选概率在规则测试中独立验证。
func _use_core_candidate(popup: PopupSkillChoice) -> void:
	var offer: SkillOffer = board.run.state.rewards.active_offer
	for existing: SkillDefinition in offer.choices:
		if existing.skill_id == &"core_drop": return
	var skill: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
	var target: SkillTarget = SkillRules.freeze_target(board.run.state, skill)
	target.coordinate = board.rules.state.get_empty_coordinates()[0]
	offer.choices[0] = skill
	offer.targets[skill.skill_id] = target
	popup.show_offer(offer)

## 交互验收使用受控候选；候选概率在规则测试中独立验证。
func _use_score_candidate(popup: PopupSkillChoice) -> void:
	var offer: SkillOffer = board.run.state.rewards.active_offer
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		if skill.skill_id != &"score_multiplier": continue
		offer.choices[0] = skill
		offer.targets[skill.skill_id] = SkillRules.freeze_target(board.run.state, skill)
		offer.unavailable.erase(skill.skill_id)
		popup.show_offer(offer)
		return


## 夹具停在正式补棋步骤；实际扣次、出生、演出与终局仍走同一推进器。
func _resume_refill() -> void:
	board.run.action_refill_count = board.run.state.next_refill_count()
	board.run.continuation = &"after_end"
	await board.resume_run(board.run)
