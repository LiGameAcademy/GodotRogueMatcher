class_name GameNewRunFlow
extends RefCounted

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

static func prepare(board: Board, checkpoint: GameCheckpointFlow) -> Dictionary:
	if checkpoint.is_busy(): return {"ok": false, "reason": "worker_busy"}
	var rules: BoardRules = BoardRules.new(BoardState.new(board.cols, board.rows), MatchSystem.MIN_MATCH_COUNT)
	var previous: int = checkpoint.previous_master_seed() if board.new_run_seeds.last_started() < 0 else -1
	var prepared: Dictionary = NewRunFactory.prepare(rules, board.game_mode.stage_config, board.new_run_seeds, null, null, previous)
	if not prepared.ok:
		board.operation_feedback.emit("hud.status.new_run_failed")
		return prepared
	if not await checkpoint.allow_new_run(): return {"ok": false, "reason": "new_run_cancelled_or_invalidation_failed"}
	return prepared
