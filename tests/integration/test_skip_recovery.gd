extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var game: Node2D
var board: Board
var hud: Hud
var skip_on_blast: bool = false
var fail_on_blast: bool = false
var corrupt_snapshot: bool = false
var fault_digest: String = ""

func before_each() -> void:
	skip_on_blast = false
	fail_on_blast = false
	corrupt_snapshot = false
	fault_digest = ""
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	add_child_autofree(game)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	board.director.step_requested.connect(_observe_step)
	board.director.step_skip_requested.connect(_observe_skip)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func _observe_step(step: PresentationStep, epoch: int, token: int) -> void:
	if step.kind != PresentationStep.Kind.MATCHES or step.matches.is_empty(): return
	if step.matches[0].cause != &"explosion": return
	if skip_on_blast: game.call("_request_skip")
	if fail_on_blast:
		fail_on_blast = false
		fault_digest = RunSnapshot.digest(RunSnapshot.capture(board.run))
		if corrupt_snapshot:
			board.director.recovery_snapshot.append(PieceState.new())
		board.director.complete_step(epoch, token, false)

func _observe_skip(step: PresentationStep, _epoch: int, _token: int) -> void:
	if step.kind != PresentationStep.Kind.MATCHES: return
	# 父协调器已应用当前代；下一代目标仍在显示中。
	for result: MatchResult in step.matches:
		if result.generation == 1:
			assert_not_null(board.get_cell(Vector2i(7, 3)).piece)

func _start_move(duration: float = 0.01) -> void:
	board.selected_piece = board.get_cell(Vector2i(5, 5)).piece
	board.move_selected_piece(board.get_cell(Vector2i(5, 4)), duration)

func _assert_display_matches_rules() -> void:
	var shown: int = 0
	for cell: Cell in board.view.get_cells():
		if cell.piece != null: shown += 1
	assert_eq(shown, board.rules.state.get_piece_count())
	for piece: PieceState in board.rules.state.get_snapshot():
		assert_same(board.get_cell(piece.coordinate).piece, board.view.get_piece(piece.piece_id))
	assert_false(board.view.is_presenting())

func test_skip_during_required_move_preserves_rule_snapshot_and_waits_for_move() -> void:
	assert_true(board.load_explosion_demo())
	_start_move()
	await GameManager.turn_started
	await wait_process_frames(2)
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_true(board.load_explosion_demo())
	_start_move(0.2)
	game.call("_request_skip")
	assert_eq(board.director._current.policy, PresentationStep.Policy.COMPLETE_REQUIRED)
	assert_false(board.can_selected)
	assert_not_null(board.get_cell(Vector2i(3, 4)).piece)
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)
	assert_eq(hud.displayed_score, 70)
	assert_false(board.director.skip_score_requested)
	_assert_display_matches_rules()

func test_active_blast_skip_and_normal_play_have_same_snapshot() -> void:
	assert_true(board.load_explosion_demo())
	_start_move()
	await GameManager.turn_started
	await wait_process_frames(2)
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_true(board.load_explosion_demo())
	skip_on_blast = true
	_start_move()
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)
	assert_eq(hud.displayed_score, 70)
	_assert_display_matches_rules()

func test_skip_score_preserves_exact_integer_and_completes_wait() -> void:
	hud.show_score(9007199254740993)
	assert_true(hud.finish_score_now())
	assert_true(await hud.wait_for_score())
	assert_eq(hud.displayed_score, 9007199254740993)
	assert_eq(GameManager.score, 0)

func test_skip_before_reward_does_not_choose_or_leak_into_next_batch() -> void:
	assert_true(board.load_explosion_demo())
	GameManager.add_score(30)
	_start_move(0.15)
	game.call("_request_skip")
	assert_false(is_instance_valid(UIManager.current_popup))
	await board.finish_presentation()
	await wait_process_frames(3)
	var popup: PopupSkillChoice = UIManager.current_popup as PopupSkillChoice
	assert_not_null(popup)
	assert_eq(hud.displayed_score, 100)
	assert_eq(board.run.state.rewards.consumed_count, 0)
	var digest: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	game.call("_request_skip")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), digest)
	assert_false(board.director.skip_score_requested)
	popup._select(0)

func test_failed_blast_recovers_committed_snapshot_without_recomputing() -> void:
	assert_true(board.load_explosion_demo())
	_start_move()
	await GameManager.turn_started
	await wait_process_frames(2)
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_true(board.load_explosion_demo())
	fail_on_blast = true
	_start_move()
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_eq(board.director.last_failure, "presentation_action_failed")
	assert_eq(board.director.error, "")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)
	assert_eq(GameManager.score, 70)
	assert_eq(board.run.state.ledger.get_entries().size(), 3)
	assert_true(board.can_selected)
	_assert_display_matches_rules()

func test_invalid_recovery_snapshot_stays_locked_and_preserves_rules() -> void:
	assert_true(board.load_explosion_demo())
	fail_on_blast = true
	corrupt_snapshot = true
	_start_move()
	await board.director.playback_failed
	await wait_process_frames(2)
	assert_false(board.can_selected)
	assert_eq(board.director.error, "presentation_action_failed")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), fault_digest)
	assert_eq(GameManager.score, 70)
	assert_false(await board.finish_presentation())

func test_retry_discards_skip_request_and_old_step_completion() -> void:
	assert_true(board.load_explosion_demo())
	_start_move(0.3)
	var epoch: int = board.director._epoch
	var token: int = board.director._waiting_token
	game.call("_request_skip")
	await board.retry_game(BoardRules.new(BoardState.new(9, 9), 5))
	board.director.complete_step(epoch, token)
	assert_true(board.can_selected)
	assert_false(board.director.skip_score_requested)
	assert_eq(GameManager.score, 0)
	_assert_display_matches_rules()

func test_lost_movement_completion_times_out_and_recovers_without_rule_replay() -> void:
	assert_true(board.load_explosion_demo())
	_start_move()
	await GameManager.turn_started
	await wait_process_frames(2)
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	assert_true(board.load_explosion_demo())
	board.director.config = board.director.config.duplicate() as PresentationConfig
	board.director.config.step_timeout_seconds = 0.1
	_start_move(0.05)
	board.selected_piece.tween.kill()
	assert_false(board.can_selected)
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_eq(board.director.last_failure, "presentation_timeout")
	assert_eq(board.director.error, "")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)
	_assert_display_matches_rules()

func test_compatibility_change_survives_two_queued_batches() -> void:
	assert_true(board.load_explosion_demo())
	_start_move(0.2)
	board._submit_plan([PresentationStep.new()])
	var extra: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	extra.piece_type = 2
	assert_true(board.place_piece(Vector2i(8, 8), extra))
	await GameManager.turn_started
	await wait_process_frames(2)
	assert_same(board.get_cell(Vector2i(8, 8)).piece, extra)
	assert_eq(board.rules.state.get_piece_id(Vector2i(8, 8)), extra.piece_id)
	_assert_display_matches_rules()

func test_final_alignment_rebuild_restores_legacy_item_mapping_without_placement() -> void:
	assert_true(board.load_explosion_demo())
	var original: ChessPiece = BoardView.PIECE_SCENE.instantiate() as ChessPiece
	original.initialize_item(ItemRegistry.create_prism_tower())
	assert_true(board.place_piece(Vector2i(8, 8), original))
	ItemEffectSystem.placed_items.append(original)
	var id: int = original.piece_id
	_start_move(0.05)
	original.is_ghost = true
	await GameManager.turn_started
	await wait_process_frames(2)
	var restored: ChessPiece = board.view.get_piece(id)
	assert_false(is_instance_valid(original))
	assert_not_null(restored.item_data)
	assert_false(restored.is_ghost)
	assert_eq(ItemEffectSystem.placed_items.size(), 1)
	assert_same(ItemEffectSystem.placed_items[0], restored)
	_assert_display_matches_rules()
