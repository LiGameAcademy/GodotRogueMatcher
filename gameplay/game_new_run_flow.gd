class_name GameNewRunFlow
extends RefCounted

static func refresh_entry(checkpoint: GameCheckpointFlow, menu: Control, popup: Control, run: RunController) -> void:
	menu.set_checkpoint_status(checkpoint.enabled, checkpoint.last_error, checkpoint.opening_progress.unlocked)
	if run != null and popup is PopupGameOver and checkpoint.opening_unlocked_run == run.state.run_id:
		popup.show_opening_unlock()

## Coordinates provisional menu presentation and prepared new-run/invalidation ordering.
static func startup(board: Board, rules: BoardRules, record_run: bool, provisional: bool) -> bool:
	var prepared: Dictionary
	if provisional:
		prepared = NewRunFactory.prepare(rules, board.game_mode.stage_config, board.new_run_seeds, RunController.new(rules, 0, board.game_mode.stage_config))
	else:
		prepared = NewRunFactory.prepare(rules, board.game_mode.stage_config, board.new_run_seeds)
	var started: bool = prepared.ok
	if not started:
		prepared = NewRunFactory.prepare(rules, board.game_mode.stage_config, board.new_run_seeds, RunController.new(rules, 0, board.game_mode.stage_config))
	await board.start_game(rules, record_run and not provisional and started, prepared.run, prepared.initial, "fixture" if provisional or not started else "human")
	if not started: board.operation_feedback.emit("hud.status.new_run_failed")
	return started

static func prepare(board: Board, checkpoint: GameCheckpointFlow, choose_opening: bool = false) -> Dictionary:
	if checkpoint.is_busy() or checkpoint.opening_choice.visible: return {"ok": false, "reason": "worker_busy"}
	if choose_opening and checkpoint.enabled and checkpoint.use_snapshot and board.game_mode.mode_id == &"stage_challenge":
		return await _prepare_with_choice(board, checkpoint, checkpoint.opening_choice)
	return await _prepare_candidate(board, checkpoint, &"standard")

static func _prepare_with_choice(board: Board, checkpoint: GameCheckpointFlow, dialog: OpeningChoice) -> Dictionary:
	var selected: StringName = &"standard"
	while true:
		selected = await dialog.choose(checkpoint.opening_progress.unlocked, selected)
		dialog.hide()
		if selected == &"": return {"ok": false, "reason": "opening_cancelled"}
		var prepared: Dictionary = await _prepare_candidate(board, checkpoint, selected)
		if prepared.ok or prepared.reason != "abandon_cancelled": return prepared
	return {"ok": false, "reason": "opening_cancelled"}

static func _prepare_candidate(board: Board, checkpoint: GameCheckpointFlow, opening: StringName) -> Dictionary:
	var rules: BoardRules = BoardRules.new(BoardState.new(board.cols, board.rows), MatchSystem.MIN_MATCH_COUNT)
	var previous: int = checkpoint.previous_master_seed() if board.new_run_seeds.last_started() < 0 else -1
	var prepared: Dictionary = NewRunFactory.prepare(rules, board.game_mode.stage_config, board.new_run_seeds, null, null, previous, opening)
	if not prepared.ok:
		board.operation_feedback.emit("hud.status.new_run_failed")
		return prepared
	if not await checkpoint.allow_new_run():
		return {"ok": false, "reason": "abandon_cancelled" if checkpoint.abandon_cancelled else "new_run_cancelled_or_invalidation_failed"}
	return prepared

static func result_data(checkpoint: GameCheckpointFlow, run: RunController, score: int) -> Dictionary:
	return {
		"score": score,
		"summary": HudDetails.summary(run.state),
		"run_state": run.state,
		"can_continue": run.can_continue_challenge(),
		"opening_unlocked": checkpoint.opening_unlocked_run == run.state.run_id,
	}

static func result_can_close(checkpoint: GameCheckpointFlow, run: RunController, already_unlocked: bool, popup: Control) -> bool:
	if not checkpoint.last_error.is_empty(): return false
	if not already_unlocked and checkpoint.opening_unlocked_run == run.state.run_id and popup is PopupGameOver:
		popup.show_opening_unlock()
		return false
	return true
