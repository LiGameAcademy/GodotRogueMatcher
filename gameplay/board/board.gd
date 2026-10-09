extends Node2D
class_name Board

## M1兼容协调器：旧回合流程调用规则入口，表现由独立BoardView消费。
signal initialized
signal presentation_updated
signal selection_changed(piece: PieceState, has_fuse: bool)
signal operation_feedback(message: String)
signal feedback_requested(cue: StringName)
signal run_reset
## Game显式提供兄弟HUD的等待入口，不从棋盘查找UI节点。
var score_presenter: Callable

@export var rows: int = 9
@export var cols: int = 9
@export var grid_gap: Vector2 = Vector2(1, 1)
var cell_size: Vector2 = Vector2(64, 64)
var rules: BoardRules
var run: RunController
var telemetry_factory: TelemetryFactory
var observation: BoardObservation = BoardObservation.new()
var can_selected: bool = false
var _generation: int = 0
var _presented_events: Dictionary[int, bool] = {}
var _score_presentation_pending: bool = false
var _compatibility_changed: bool = false
var _turn_in_progress: bool = false
var input_buffer: BoardInputBuffer = BoardInputBuffer.new()
var selected_piece: ChessPiece = null:
	set(value):
		if is_instance_valid(selected_piece):
			selected_piece.deselected()
		selected_piece = value
		if is_instance_valid(selected_piece):
			selected_piece.selected()
			var piece: PieceState = rules.state.get_piece(selected_piece.piece_id)
			selection_changed.emit(piece, run.state.explosion.instances.has(selected_piece.piece_id))
		else:
			selection_changed.emit(null, false)

@onready var view: BoardView = $BoardView
@onready var director: PresentationDirector = $PresentationDirector

func _ready() -> void:
	add_to_group("board")
	view.cell_pressed.connect(_on_coordinate_pressed)
	view.piece_activated.connect(_on_piece_activated)
	director.step_requested.connect(_on_presentation_step_requested)
	director.step_skip_requested.connect(_on_step_skip_requested)
	director.playback_failed.connect(_on_playback_failed)
	view.piece_removing.connect(_on_piece_removing)
	view.match_visualized.connect(_on_match_visualized)
	director.busy_changed.connect(view.set_playback_pending)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: observation.focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: observation.focused(true)
	elif what == NOTIFICATION_PAUSED: observation.paused(not UIManager.current_popup is PopupSkillChoice)
	elif what == NOTIFICATION_UNPAUSED: observation.paused(false)
	if run == null or run.recorder == null or run.recorder.ended: return
	if what == NOTIFICATION_PAUSED:
		# 技能面板使用树暂停来接管输入，其等待单独归类。
		run.recorder.set_interval("choice" if UIManager.current_popup is PopupSkillChoice else "pause")
	elif what == NOTIFICATION_UNPAUSED:
		run.recorder.set_interval("input" if can_selected else "busy")

func _exit_tree() -> void:
	director.cancel()
	if run == null or run.recorder == null: return
	if not run.state.rule_error.is_empty(): run.recorder.finish(run, "rule_error", run.state.rule_error)
	elif run.state.is_game_over: run.recorder.finish(run, "completed", "board_full")
	else: run.recorder.finish(run, "abandoned", "scene_closed")

#region 初始化与重试
## 规则对象由Game显式注入，重试传入全新的状态。
func start_game(board_rules: BoardRules, record_run: bool = false) -> void:
	run_reset.emit()
	cancel_buffered_input()
	_turn_in_progress = false
	_generation += 1
	director.cancel()
	var generation: int = _generation
	can_selected = false
	selected_piece = null
	rules = board_rules
	_presented_events.clear()
	_score_presentation_pending = false
	_compatibility_changed = false
	view.configure(cols, rows, cell_size, grid_gap)
	if run != null and run.recorder != null: run.recorder.finish(run, "abandoned", "restart")
	run = RunController.new(rules, randi())
	GameManager.reset_game(run)
	# 先更换本局，再关闭旧奖励；等待中的回调会识别旧run并退出。
	UIManager.close_popup()
	await get_tree().process_frame
	var initial: RunStepResult = run.initialize()
	if record_run or telemetry_factory != null:
		run.recorder = RunRecorder.new()
		observation.attach(telemetry_factory.attach(run.recorder, run.state.run_id) if telemetry_factory != null else null)
		run.recorder.begin(run, "human", record_run)
		observation.busy(true)
	await present_spawns(initial.spawns)
	if generation != _generation: return
	GameManager.turn_started.emit(run.state.turn_count)
	can_selected = not GameManager.is_game_over and run.state.rule_error.is_empty()
	observation.busy(false)
	initialized.emit()

func retry_game(board_rules: BoardRules) -> void:
	if run != null and run.recorder != null: run.recorder.finish(run, "abandoned", "restart")
	get_tree().paused = false
	ItemEffectSystem.placed_items.clear()
	LevelUpSystem.reset_system()
	ItemRegistry.register_all_items()
	await start_game(board_rules, true)

## 调试入口只在稳定输入点加载固定爆炸盘面。
func load_explosion_demo(mode: String = "fixture_f6") -> bool:
	if get_tree().paused or cols < 8 or rows < 6 or (not can_selected and run.state.rule_error.is_empty()):
		return false
	run_reset.emit()
	if run != null and run.recorder != null: run.recorder.finish(run, "abandoned", "fixture_restart")
	cancel_buffered_input()
	_turn_in_progress = false
	_generation += 1
	director.cancel()
	can_selected = false
	selected_piece = null
	ItemEffectSystem.placed_items.clear()
	LevelUpSystem.reset_system()
	ItemRegistry.register_all_items()
	rules = BoardRules.new(BoardState.new(cols, rows), MatchSystem.MIN_MATCH_COUNT)
	run = RunController.new(rules, 7)
	GameManager.reset_game(run)
	_presented_events.clear()
	_score_presentation_pending = false
	_compatibility_changed = false
	view.configure(cols, rows, cell_size, grid_gap)
	run.initialize(mode)
	run.recorder = RunRecorder.new()
	observation.attach(telemetry_factory.attach(run.recorder, run.state.run_id) if telemetry_factory != null else null)
	run.recorder.begin(run, "fixture")
	view.rebuild(rules.state.get_snapshot())
	refresh_ability_markers()
	_update_count_display()
	GameManager.turn_started.emit(run.state.turn_count)
	can_selected = true
	observation.busy(false)
	return true

func refresh_ability_markers() -> void:
	view.refresh_piece_details(rules.state.get_snapshot(), run.state.explosion, run.abilities.config)

## F7仅推进到下一个分数门槛，使用与正常局相同的奖励入口。
func open_skill_demo() -> bool:
	if not can_selected or get_tree().paused or GameManager.is_game_over:
		return false
	var generation: int = _generation
	can_selected = false
	selected_piece = null
	if run.recorder != null: run.recorder.finish(run, "abandoned", "debug_f7_not_balance_sample")
	GameManager.add_score(maxi(0, LevelUpSystem.next_milestone - GameManager.score))
	run.enter_rewards()
	await LevelUpSystem.resolve_pending_rewards(self)
	if generation != _generation: return false
	if not GameManager.is_game_over and run.state.rule_error.is_empty():
		run.state.phase = RunState.Phase.INPUT
		can_selected = true
	return true
#endregion

#region 单一棋盘写入口与显示适配
func place_piece(coordinate: Vector2i, piece: ChessPiece) -> bool:
	var content_id: StringName = StringName(piece.item_data.id) if piece.item_data != null else &""
	var snapshot: PieceState = rules.place_piece(coordinate, piece.piece_type, content_id, piece.is_ghost)
	if snapshot == null:
		return false
	view.show_piece(snapshot, piece)
	refresh_ability_markers()
	if director.is_busy(): _compatibility_changed = true
	_update_count_display()
	return true

func remove_piece(coordinate: Vector2i, animated: bool = false) -> bool:
	var piece_id: int = rules.state.get_piece_id(coordinate)
	var snapshot: PieceState = rules.remove_piece(piece_id)
	if snapshot == null:
		return false
	run.state.explosion.instances.erase(piece_id)
	var piece: ChessPiece = view.get_piece(piece_id)
	if selected_piece == piece:
		selected_piece = null
	if is_instance_valid(piece) and piece.item_data != null:
		ItemEffectSystem.unregister_item(piece)
	view.remove_piece(snapshot, animated)
	if director.is_busy(): _compatibility_changed = true
	_update_count_display()
	return true

func set_piece_color(coordinate: Vector2i, match_color: int) -> bool:
	var piece_id: int = rules.state.get_piece_id(coordinate)
	if not rules.set_piece_color(piece_id, match_color):
		return false
	view.show_color(piece_id, match_color)
	refresh_ability_markers()
	if director.is_busy(): _compatibility_changed = true
	return true

## 只在等待输入的稳定点重建；播放/奖励期间拒绝，避免重入旧回合。
func rebuild_view() -> bool:
	if not can_selected or get_tree().paused:
		return false
	selected_piece = null
	_restore_view(rules.state.get_snapshot())
	return true

## 重建不是获得道具，不重新触发ON_PLACE。
func _restore_view(snapshot: Array[PieceState]) -> void:
	view.rebuild(snapshot)
	refresh_ability_markers()
	_sync_items()

func _sync_items() -> void:
	ItemEffectSystem.placed_items.clear()
	for cell: Cell in view.get_cells():
		var piece: ChessPiece = cell.piece
		if is_instance_valid(piece) and piece.item_data != null: ItemEffectSystem.placed_items.append(piece)

## 消费已经提交的离场快照；旧道具信号暂保留为M3兼容边界。
func present_matches(results: Array[MatchResult]) -> void:
	_submit_plan(PlaybackPlanBuilder.matches(results))

func _submit_plan(steps: Array[PresentationStep]) -> void:
	for step: PresentationStep in steps:
		var pending: Array[MatchResult] = []
		for result: MatchResult in step.matches:
			if _presented_events.has(result.score_entry.event_id): continue
			_presented_events[result.score_entry.event_id] = true
			pending.append(result)
		step.matches = pending
		if not pending.is_empty(): _score_presentation_pending = true
	director.enqueue(steps, rules.state.get_snapshot(), true)

func _on_piece_removing(piece: ChessPiece) -> void:
	if selected_piece == piece: selected_piece = null
	if piece.item_data != null: ItemEffectSystem.unregister_item(piece)

func _on_match_visualized(result: MatchResult, cells: Array[Cell]) -> void:
	if result.cause == &"match": MatchSystem.match_made.emit(result.score_entry.final_score, result.center, cells)

## 演出完成后再广播已提交分数和检查门槛；重试取消旧批次。
func finish_presentation() -> bool:
	var active_run: RunController = run
	if not await director.wait_until_idle(): return false
	if not await view.wait_for_presentation() or run != active_run: return false
	if _score_presentation_pending:
		_score_presentation_pending = false
		GameManager.publish_score()
	if score_presenter.is_valid() and not await score_presenter.call(): return false
	if run != active_run: return false
	_compatibility_changed = false
	director.clear_skip_request()
	presentation_updated.emit()
	return true

## 技能应用只消费已提交结果；落子查线也不会重复计分。
func present_skill_result(result: SkillApplyResult) -> void:
	_submit_plan(PlaybackPlanBuilder.skill(result, director.config.spawn_duration))
	refresh_ability_markers()
	_update_count_display()

func _on_presentation_step_requested(step: PresentationStep, epoch: int, token: int) -> void:
	var completed: bool = true
	view.set_step_policy(step.policy)
	match step.kind:
		PresentationStep.Kind.MOVE:
			completed = await view.animate_move(step.movement, step.duration)
		PresentationStep.Kind.SPAWN:
			for piece: PieceState in step.pieces: view.animate_spawn(piece, step.duration)
		PresentationStep.Kind.REMOVE:
			for piece: PieceState in step.pieces: view.remove_piece(piece, true)
		PresentationStep.Kind.MATCHES:
			var cue: StringName = &"match"
			for result: MatchResult in step.matches:
				if result.cause == &"explosion": cue = &"blast"
			if not step.matches.is_empty(): feedback_requested.emit(cue)
			view.animate_matches(step.matches)
		PresentationStep.Kind.ALIGN:
			# 旧公开写入口的额外提交只在全部步骤结束后纳入对齐。
			var ending: Array[PieceState] = rules.state.get_snapshot() if _compatibility_changed else step.pieces
			completed = (_compatibility_changed and director.has_queued_steps()) or view.align_snapshot(ending)
			if completed: _sync_items()
	if completed: completed = await view.wait_for_animations()
	if not director.is_current(epoch, token): return
	if completed:
		refresh_ability_markers()
		_update_count_display()
	director.complete_step(epoch, token, completed)

func _on_step_skip_requested(step: PresentationStep, epoch: int, token: int) -> void:
	director.complete_step(epoch, token, view.skip_step(step))

func _on_playback_failed(reason: String) -> void:
	can_selected = false
	cancel_buffered_input("presentation_error")
	var snapshot: Array[PieceState] = rules.state.get_snapshot() if _compatibility_changed else director.recovery_snapshot
	if not PlaybackPlanBuilder.valid_snapshot(snapshot, Vector2i(cols, rows)):
		operation_feedback.emit("演出异常，无法恢复盘面：" + reason)
		return
	selected_piece = null
	view.cancel_animations()
	_restore_view(snapshot)
	_compatibility_changed = false
	_score_presentation_pending = true
	director.confirm_recovery()
	operation_feedback.emit("演出异常，已对齐本次结果")

func set_playback_fast(fast: bool) -> void:
	view.presentation_speed = director.config.fast_speed if fast else director.config.normal_speed

func get_cell(coordinate: Vector2i) -> Cell:
	return view.get_cell(coordinate)

func get_empty_cells() -> Array[Cell]:
	var cells: Array[Cell] = []
	for coordinate: Vector2i in rules.state.get_empty_coordinates():
		cells.append(get_cell(coordinate))
	return cells

func get_cells(coordinates: Array[Vector2i]) -> Array[Cell]:
	var cells: Array[Cell] = []
	for coordinate: Vector2i in coordinates:
		cells.append(get_cell(coordinate))
	return cells

func has_piece(coordinate: Vector2i) -> bool:
	return rules.state.get_piece_id(coordinate) != 0

func is_board_empty() -> bool:
	return rules.state.get_piece_count() == 0
#endregion

#region 旧回合流程兼容
func _on_cell_pressed(cell: Cell) -> void:
	await _on_coordinate_pressed(cell.coordinate)

func move_selected_piece(target_cell: Cell, duration: float = 0.5, buffered_wait_ms: int = -1, input_id: String = "") -> bool:
	if not can_selected or GameManager.is_game_over or not is_instance_valid(selected_piece) or target_cell == null:
		return false
	var command: MovePieceCommand = MovePieceCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = selected_piece.piece_id
	command.target = target_cell.coordinate
	command.buffered = buffered_wait_ms >= 0
	command.buffered_wait_ms = maxi(0, buffered_wait_ms)
	return await _execute_action(command, duration, input_id)

func _on_piece_activated(coordinate: Vector2i) -> void:
	if not can_selected or get_tree().paused or GameManager.is_game_over: return
	var command: DetonateCoreCommand = DetonateCoreCommand.new(run.state.run_id, run.last_command_id + 1, run.state.action_id)
	command.piece_id = rules.state.get_piece_id(coordinate)
	await _execute_action(command, director.config.spawn_duration)

func _execute_action(command: RunCommand, duration: float, input_id: String = "") -> bool:
	if input_id.is_empty(): input_id = observation.input("detonate" if command is DetonateCoreCommand else "move", command.buffered)
	observation.busy(true)
	var outcome: CommandResult = run.execute_command(command)
	observation.resolve(input_id, "submitted" if outcome.accepted else "rejected", outcome.reason, str(command.command_id), command.buffered_wait_ms)
	var turn: TurnResult = outcome.turn

	if not run.state.rule_error.is_empty():
		can_selected = false
		push_error(run.state.rule_error)
		return false
	if not outcome.accepted or turn == null:
		observation.busy(false)
		selected_piece = null
		return false
	var generation: int = _generation
	can_selected = false
	_turn_in_progress = true
	# 移动已经提交，演出只使用路径结果，不决定是否合法。
	var plan: Array[PresentationStep] = []
	if turn.move != null: plan = PlaybackPlanBuilder.move(turn.move, duration)
	if not turn.removed.is_empty():
		var removal: SkillApplyResult = SkillApplyResult.new()
		removal.removed = turn.removed
		plan.append_array(PlaybackPlanBuilder.skill(removal, duration))
	plan.append_array(PlaybackPlanBuilder.matches(turn.matches))
	_submit_plan(plan)
	if not await director.wait_until_idle(): return false
	if generation != _generation:
		return false
	selected_piece = null
	await _continue_run(generation)
	if generation != _generation: return false
	if not director.error.is_empty(): return false
	can_selected = not GameManager.is_game_over and run.state.rule_error.is_empty()
	_turn_in_progress = false
	_resume_buffered_input()
	return true

## 真人和无界面驱动共用advance；这里仅等待和消费阶段结果。
func _continue_run(generation: int) -> void:
	while generation == _generation:
		if not await finish_presentation(): return
		var step: RunStepResult = run.advance()
		match step.kind:
			&"offer": await LevelUpSystem.resolve_pending_rewards(self)
			&"end_turn":
				refresh_ability_markers()
				GameManager.turn_ended.emit(run.state.turn_count)
			&"spawn":
				await present_spawns(step.spawns)
				present_matches(step.matches)
			&"input":
				GameManager.turn_started.emit(run.state.turn_count)
				if run.recorder != null: run.recorder.set_interval("input")
				observation.busy(false)
				return
			&"finished":
				GameManager.finish_game()
				if run.recorder != null: run.recorder.finish(run, "completed", "board_full")
				return
			&"error":
				if run.recorder != null: run.recorder.finish(run, "rule_error", run.state.rule_error)
				return

func present_spawns(spawns: Array[SpawnResult]) -> void:
	var active_run: RunController = run
	_submit_plan(PlaybackPlanBuilder.spawns(spawns, director.config.spawn_duration))
	if not await finish_presentation() or run != active_run: return
	_update_count_display()

func _on_coordinate_pressed(coordinate: Vector2i) -> void:
	if GameManager.is_game_over or get_tree().paused or not run.state.rule_error.is_empty():
		observation.resolve(observation.input("click"), "discarded", "game_over" if GameManager.is_game_over else "paused_or_error")
		return
	if not can_selected:
		if _turn_in_progress: _buffer_input(coordinate)
		else: observation.resolve(observation.input("click"), "discarded", "busy")
		return
	var piece_id: int = rules.state.get_piece_id(coordinate)
	if piece_id != 0:
		selected_piece = view.get_piece(piece_id)
		observation.resolve(observation.input("select"), "selected", "piece_selected")
	elif is_instance_valid(selected_piece):
		await move_selected_piece(get_cell(coordinate))
	else: observation.resolve(observation.input("click"), "discarded", "no_selection")

func cancel_buffered_input(reason: String = "cancelled") -> void:
	input_buffer.cancel(view, observation, reason)

func _buffer_input(coordinate: Vector2i) -> void:
	var message: String = input_buffer.receive(coordinate, view, rules.state, observation)
	if not message.is_empty(): operation_feedback.emit(message)

func _resume_buffered_input() -> void:
	var id: int = input_buffer.piece_id
	var target: Vector2i = input_buffer.target
	var input_id: String = observation.buffered_input
	observation.buffered_input = ""
	cancel_buffered_input()
	if not can_selected or rules.state.get_piece(id) == null:
		observation.resolve(input_id, "discarded", "piece_missing_or_busy")
		if id != 0: operation_feedback.emit("暂存棋子已离场，操作已取消")
		return
	selected_piece = view.get_piece(id)
	if target != Vector2i(-1, -1):
		# 下一帧在最新棋盘重新寻路，不与当前回合重入，也不跨局执行。
		_commit_buffered_move.call_deferred(_generation, id, target, Time.get_ticks_msec() - input_buffer.started_ms, input_id)
	else: observation.resolve(input_id, "selected", "buffered_selection")

func _commit_buffered_move(generation: int, id: int, target: Vector2i, waiting_ms: int, input_id: String = "") -> void:
	if generation != _generation or not can_selected or get_tree().paused:
		observation.resolve(input_id, "discarded", "stale_run_or_busy")
		return
	if not is_instance_valid(selected_piece) or selected_piece.piece_id != id or rules.state.get_piece_id(target) != 0:
		observation.resolve(input_id, "discarded", "piece_changed_or_target_occupied")
		operation_feedback.emit("暂存目标失效，请重新选择")
		return
	await move_selected_piece(get_cell(target), 0.5, waiting_ms, input_id)

func _update_count_display() -> void:
	# 旧HUD兼容字段是派生显示值，不能用于占格或寻路决策。
	GameManager.piece_count = rules.state.get_piece_count()
#endregion
