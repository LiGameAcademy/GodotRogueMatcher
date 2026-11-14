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
				# Web uses one thread: give the board a frame between preparing the offer,
				# freezing its checkpoint, and building the reward popup.
				if OS.has_feature("web"):
					await board.get_tree().process_frame
					if not _same_offer(board, active, step.offer): return
				board.checkpoint_reached.emit(active)
				if OS.has_feature("web") and not board.hold_at_checkpoint:
					await board.get_tree().process_frame
					if not _same_offer(board, active, step.offer): return
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

static func _same_offer(board: Board, active: RunController, offer: SkillOffer) -> bool:
	return is_instance_valid(board) and board.is_inside_tree() and board.run == active and not active.is_retired() and active.state.rewards.active_offer == offer

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

## A playback batch has one cause and generation, including legal empty ability results.
static func play_matches(board: Board, results: Array[MatchResult]) -> void:
	if results.is_empty(): return
	var first: MatchResult = results.front()
	match first.cause:
		&"explosion": board.feedback_requested.emit(&"blast")
		&"line_clear": board.feedback_requested.emit(&"sweep")
		_: board.match_feedback_requested.emit(first.generation)
	board.view.animate_matches(results)
