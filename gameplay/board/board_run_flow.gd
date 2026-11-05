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
					push_warning("Reward unavailable: " + active.state.rule_error)
					board.operation_feedback.emit("hud.status.unavailable")
					return
				board.checkpoint_reached.emit(active)
				if not board.hold_at_checkpoint: board.reward_requested.emit(active, step.offer)
				return
			&"end_turn":
				board.refresh_ability_markers()
				GameManager.turn_ended.emit(active.state.turn_count)
			&"spawn", &"recovery":
				await board.present_spawns(step.spawns, true)
				board.present_matches(step.matches)
			&"input":
				GameManager.turn_started.emit(active.state.turn_count)
				if active.recorder != null: active.recorder.set_interval("input")
				board.observation.busy(false)
				board.checkpoint_reached.emit(active)
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

## Captures committed birth plans; initial and skill births never claim preview slots.
static func present_spawns(board: Board, spawns: Array[SpawnResult], from_preview: bool) -> void:
	if not spawns.is_empty(): board.feedback_requested.emit(&"spawn")
	var active: RunController = board.run
	if from_preview and board.spawn_preview_prepare.is_valid(): board.spawn_preview_prepare.call(spawns)
	board._submit_plan(PlaybackPlanBuilder.spawns(spawns, board.director.config.spawn_duration, from_preview))
	if not await board.finish_presentation() or board.run != active: return
	board._update_count_display()

## The parent supplies a viewport-space origin only for a visible matching slot.
static func present_birth(board: Board, step: PresentationStep) -> void:
	for piece: PieceState in step.pieces:
		var origin: Variant = null
		if step.preview_slot >= 0 and board.spawn_origin_provider.is_valid():
			origin = board.spawn_origin_provider.call(piece, step.preview_slot)
		board.view.animate_spawn(piece, step.duration, origin)
