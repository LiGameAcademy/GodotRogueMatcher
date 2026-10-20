class_name BoardRunFlow
extends RefCounted

## Presentation driver and recording lifecycle; consumes the authoritative run's steps.
static func continue_run(board: Board, active: RunController) -> void:
	while is_instance_valid(board) and board.run == active:
		if not await board.finish_presentation(): return
		var step: RunStepResult = active.advance()
		if step.challenge != null and step.challenge.goal_score_entry != null:
			board.mark_score_pending()
			board.goal_bonus_ready.emit(step.challenge.goal_score_entry)
		match step.kind:
			&"offer":
				board.can_selected = false
				if step.offer == null:
					board.operation_feedback.emit(active.state.rule_error)
					return
				board.reward_requested.emit(active, step.offer)
				return
			&"end_turn":
				board.refresh_ability_markers()
				GameManager.turn_ended.emit(active.state.turn_count)
			&"spawn":
				await board.present_spawns(step.spawns)
				board.present_matches(step.matches)
			&"input":
				GameManager.turn_started.emit(active.state.turn_count)
				if active.recorder != null: active.recorder.set_interval("input")
				board.observation.busy(false)
				return
			&"finished":
				GameManager.finish_game()
				if active.recorder != null:
					if active.can_continue_challenge(): active.recorder.flush_pending()
					else: finalize(active, "finished")
				return
			&"error":
				if active.recorder != null: active.recorder.finish(active, "rule_error", active.state.rule_error)
				return

## A pending victory becomes completed only when the player ends it; active continuation is abandoned on exit.
static func finalize(run: RunController, reason: String) -> void:
	if run == null or run.recorder == null or run.recorder.ended: return
	if not run.state.rule_error.is_empty(): run.recorder.finish(run, "rule_error", run.state.rule_error)
	elif run.state.is_game_over: run.recorder.finish(run, "completed", String(run.state.end_reason))
	else: run.recorder.finish(run, "abandoned", reason)
