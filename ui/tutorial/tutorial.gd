class_name Tutorial
extends Control

signal finished(completed: bool)

@onready var title: Label = %Title
@onready var instructions: Label = %Instructions
@onready var status: Label = %Status
@onready var score: Label = %Score
@onready var next_button: Button = %Next
@onready var skip_button: Button = %Skip
@onready var board_area: Control = %BoardArea
@onready var view: BoardView = %BoardView
@onready var choices: PopupSkillChoice = %Choices
var session: TutorialSession = TutorialSession.new()
var _selected: int = 0
var _busy: bool = false
var _completed: bool = false
var _epoch: int = 0

func _ready() -> void:
	board_area.gui_input.connect(_board_input)
	board_area.resized.connect(_layout_board)
	next_button.pressed.connect(_next)
	skip_button.pressed.connect(_skip)
	choices.skill_selected.connect(_choose)
	choices.color_skill_selected.connect(_choose)

func start(low_effects: bool = false) -> void:
	cancel()
	session.reset()
	view.configure(5, 5, Vector2(64, 64), Vector2(1, 1))
	view.set_low_effects(low_effects)
	show()
	_show_lesson()

func cancel() -> void:
	_epoch += 1
	_busy = false
	choices.hide()
	view.clear_display()
	hide()

func _show_lesson() -> void:
	_selected = 0
	_completed = false
	_busy = false
	title.text = "%d / 4 · %s" % [session.lesson + 1, TutorialSession.CONFIG.titles[session.lesson]]
	instructions.text = TutorialSession.CONFIG.instructions[session.lesson]
	status.text = "这是独立练习，不计入正式局。"
	next_button.text = "完成练习" if session.lesson == 3 else "下一步 →"
	next_button.disabled = true
	view.rebuild(session.run.state.rules.state.get_snapshot())
	_refresh_details()
	_layout_board()
	var config: TutorialConfig = TutorialSession.CONFIG
	view.get_cell(config.core if session.lesson == 3 else (config.spare if session.lesson == 1 else config.source)).highlight()
	if session.lesson != 3: view.get_cell(config.refill_target if session.lesson == 1 else config.target).highlight()

func _layout_board() -> void:
	var bounds: Rect2 = view.get_display_rect()
	if not bounds.has_area(): return
	var factor: float = minf((board_area.size.x - 32.0) / bounds.size.x, (board_area.size.y - 32.0) / bounds.size.y)
	view.scale = Vector2.ONE * maxf(0.01, factor)
	view.position = (board_area.size - bounds.size * factor) * 0.5 - bounds.position * factor

func _board_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or _busy or _completed: return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT: return
	var point: Vector2 = view.transform.affine_inverse() * click.position
	var coordinate: Vector2i = Vector2i(roundi(point.x / 65.0), roundi(point.y / 65.0))
	if not session.run.state.rules.state.is_valid_coordinate(coordinate): return
	if session.lesson == 3:
		if click.double_click: _execute(session.detonate(coordinate))
		else: status.text = "双击标有「爆」的棋子来主动引爆。"
		return
	var piece: PieceState = session.run.state.rules.state.get_piece_at(coordinate)
	if piece != null:
		_selected = piece.piece_id
		status.text = "已选中棋子 · 再点击高亮空格"
	elif _selected != 0: _execute(session.move(_selected, coordinate))

func _execute(result: CommandResult) -> void:
	if not result.accepted:
		status.text = result.reason
		return
	_busy = true
	var epoch: int = _epoch
	status.text = "正在结算…"
	if result.turn.move != null:
		if not await view.animate_move(result.turn.move, 0.2) or epoch != _epoch: return
	for removed: PieceState in result.turn.removed: view.remove_piece(removed, true)
	view.animate_matches(result.turn.matches)
	if not await view.wait_for_animations() or epoch != _epoch: return
	_refresh_details()
	await _advance(epoch)

func _advance(epoch: int) -> void:
	# 与正式局一样，在已提交结果播放后才推进到技能选择。
	for iteration: int in range(16):
		if epoch != _epoch: return
		var step: RunStepResult = session.run.advance()
		if step.kind == &"offer":
			choices.show_offer(step.offer, "练习：选择一项技能。选择只影响练习盘。")
			choices.show()
			return
		for spawn: SpawnResult in step.spawns:
			view.animate_spawn(spawn.piece, 0.18)
			if not await view.wait_for_animations() or epoch != _epoch: return
			view.animate_matches(spawn.matches)
			if not await view.wait_for_animations() or epoch != _epoch: return
		view.animate_matches(step.matches)
		if not await view.wait_for_animations() or epoch != _epoch: return
		if step.kind == &"input":
			view.align_snapshot(session.run.state.rules.state.get_snapshot())
			_refresh_details()
			_busy = false
			_completed = true
			status.text = "完成！观察棋盘后，点击右下方继续。"
			next_button.disabled = false
			next_button.grab_focus()
			return
		if step.kind == &"error" or step.kind == &"finished": break
	status.text = "练习未能继续，请返回并重新开始练习。"
	_busy = false

func _choose(offer_id: int, skill_id: StringName, color: int = -1) -> void:
	var result: CommandResult = session.choose(offer_id, skill_id, color)
	if not result.accepted:
		choices.show_error(result.reason)
		return
	choices.hide()
	# 技能的移除/出生结果由规则提交；对齐练习视图，不触碰正式局。
	view.rebuild(session.run.state.rules.state.get_snapshot())
	_refresh_details()
	await _advance(_epoch)

func _refresh_details() -> void:
	score.text = "练习得分 %d · 空位 %d / 25" % [session.run.state.ledger.total, session.run.state.rules.state.get_empty_coordinates().size()]
	view.refresh_piece_details(session.run.state.rules.state.get_snapshot(), session.run.state.explosion, session.run.abilities.config)

func _next() -> void:
	if not _completed or _busy: return
	if session.lesson == 3:
		cancel()
		finished.emit(true)
	else:
		session.next_lesson()
		_show_lesson()

func _skip() -> void:
	cancel()
	finished.emit(false)
