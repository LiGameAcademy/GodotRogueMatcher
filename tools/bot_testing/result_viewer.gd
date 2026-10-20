class_name ResultViewer
extends Node2D

@export var record_path: String = ""
@onready var view: BoardView = $BoardView
@onready var path_input: LineEdit = $Controls/Path/PathInput
@onready var status: Label = $Controls/Status
@onready var play: CheckButton = $Controls/Actions/Play
@onready var clock: Timer = $Clock
var records: Array[Dictionary] = []
var cursor: int = 0
var busy: bool = false
var error: String = ""
var dimensions: Vector2i
var current_state: Dictionary = {}
var _generation: int = 0
var _skill: Dictionary = {}

func _ready() -> void:
	$Controls/Path/Load.pressed.connect(_load_path)
	$Controls/Actions/Step.pressed.connect(step)
	$Controls/Actions/Speed.item_selected.connect(_speed_selected)
	if has_node("Controls/Actions/Validate"):
		$Controls/Actions/Validate.pressed.connect(validate_rules)
	clock.timeout.connect(_tick)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): record_path = args[0]
	path_input.text = record_path
	if not record_path.is_empty(): load_record(record_path)

func load_record(path: String) -> bool:
	_generation += 1
	busy = false
	play.button_pressed = false
	_skill = {}
	var reader: RuleReplay = RuleReplay.new()
	records = reader.read_file(path)
	error = reader.error
	if records.is_empty() or records[0].get("kind") != "Header" or records[0].get("schema_version") != RunRecorder.SCHEMA: return _fail("不支持的记录格式")
	var header: Dictionary = records[0]
	if not header.get("config") is Dictionary or not header.get("initial") is Dictionary: return _fail("缺少初始盘面")
	for key: String in ["columns", "rows"]:
		if not CommandCodec.valid_integer(header.config.get(key)): return _fail("无效棋盘尺寸")
	dimensions = Vector2i(header.config.columns.to_int(), header.config.rows.to_int())
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 64 or dimensions.y > 64: return _fail("无效棋盘尺寸")
	if not RecordViewData.valid_state(header.initial, dimensions): return _fail("无效初始盘面")
	for row: Dictionary in records:
		if not RecordViewData.valid_record(row, dimensions): return _fail("无效记录结构：seq=" + String(row.get("seq", "?")))
	view.configure(dimensions.x, dimensions.y, Vector2(64, 64), Vector2.ONE)
	cursor = 1
	if not _show_state(header.initial): return false
	var read_note: String = ""
	if not error.is_empty():
		read_note = "\n读取警告：" + RuleReplay.describe_error(error)
	status.text = "结果观看 · 不验证规则一致性（可用“验证回放”）\n%s%s" % [path, read_note]
	return true

## Exact RuleReplay against current build; presentation speed does not affect the check.
func validate_rules() -> void:
	if path_input.text.is_empty() and record_path.is_empty():
		status.text = "验证失败：未指定记录路径"
		return
	var path: String = path_input.text if not path_input.text.is_empty() else record_path
	var replay: RuleReplay = RuleReplay.new()
	if replay.replay_file(path):
		status.text = "验证通过：完整状态重算一致（规则版 %s · 已检 %d 条）" % [RunSnapshot.RULES_VERSION, replay.checked_records]
	else:
		status.text = "验证失败：%s\n机器码：%s" % [RuleReplay.describe_error(replay.error), replay.error]

func step() -> void:
	if busy or records.is_empty(): return
	busy = true
	var generation: int = _generation
	while cursor < records.size():
		var row: Dictionary = records[cursor]
		cursor += 1
		match row.get("kind"):
			"SkillAcquired": _skill = row
			"Offer":
				status.text = "候选：" + ", ".join(row.offer.choices)
				break
			"RuleResult":
				await _present(row)
				if generation != _generation: return
				break
			"Footer":
				_show_state(row.final)
				status.text += "\n结束：%s / %s" % [row.status, row.reason]
				play.button_pressed = false
				break
	if cursor >= records.size(): play.button_pressed = false
	busy = false

func _present(row: Dictionary) -> void:
	var generation: int = _generation
	if row.has("before") and not _show_state(row.before): return
	var movement: Dictionary = row.get("move", {})
	if not movement.is_empty():
		var result: BoardMoveResult = BoardMoveResult.new()
		if not CommandCodec.valid_integer(movement.get("piece_id")) or not movement.get("path") is Array:
			_fail("无效移动路径")
			return
		result.piece_id = movement.piece_id.to_int()
		for cell: Variant in movement.path:
			var coordinate: Vector2i = RecordViewData.coordinate(cell)
			if view.get_cell(coordinate) == null:
				_fail("移动路径越界")
				return
			result.path.append(coordinate)
		if view.get_piece(result.piece_id) != null and not result.path.is_empty():
			if view.get_cell(result.path[0]).piece != view.get_piece(result.piece_id):
				_fail("移动起点不一致")
				return
			for index: int in range(1, result.path.size()):
				var offset: Vector2i = result.path[index] - result.path[index - 1]
				if absi(offset.x) + absi(offset.y) != 1 or view.get_cell(result.path[index]).piece != null:
					_fail("移动路径不连续或经过占格")
					return
			await view.animate_move(result, 0.4 / view.presentation_speed)
			if generation != _generation: return
	for birth: Dictionary in row.get("births", []):
		_show_piece(birth.piece)
		_events(birth.events)
		if not await view.wait_for_presentation() or generation != _generation: return
	if not _skill.is_empty():
		for data: Dictionary in _skill.created: _show_piece(data)
		for data: Dictionary in _skill.get("transformed", []): view.animate_transform(RecordViewData.piece(data), 0.12)
		for data: Dictionary in _skill.removed:
			_remove_piece(data)
		_skill = {}
	for removed: Dictionary in row.get("removed", []): _remove_piece(removed)
	_events(row.get("events", []))
	if not await view.wait_for_presentation() or generation != _generation: return
	_show_state(row.after)
	var activations: Array = row.get("activations", [])
	if not activations.is_empty():
		var lines: PackedStringArray = []
		for activation: Dictionary in activations:
			lines.append("%s · 来源棋%d · 消费=%s · 影响%d" % [String(activation.get("ability_id", "?")), int(str(activation.get("owner_id", "0"))), str(activation.get("consumed", false)), int(str(activation.get("affected_count", "0")))])
		status.text += "\n触发：" + " | ".join(lines)

func _events(events: Array) -> void:
	for event: Dictionary in events:
		if event.cause == "explosion": view.show_blast(RecordViewData.coordinate(event.center), String(event.radius).to_int())
		elif event.cause == "line_clear":
			view.show_line_clear(RecordViewData.coordinate(event.center), int(str(event.get("line_axis", "-1"))), int(str(event.radius)), int(str(event.get("cross_radius", "-1"))))
		for data: Dictionary in event.removed:
			_remove_piece(data)

func _remove_piece(data: Dictionary) -> void:
	var piece: PieceState = RecordViewData.piece(data)
	if piece == null: return
	var cell: Cell = view.get_cell(piece.coordinate)
	if cell != null and cell.piece == view.get_piece(piece.piece_id) and cell.piece != null: view.remove_piece(piece, true)

func _show_piece(data: Dictionary) -> void:
	var piece: PieceState = RecordViewData.piece(data)
	if piece == null or view.get_cell(piece.coordinate) == null or view.get_cell(piece.coordinate).piece != null: return
	view.show_piece(piece, BoardView.PIECE_SCENE.instantiate() as ChessPiece)

func _show_state(state: Dictionary) -> bool:
	var pieces: Array[PieceState] = RecordViewData.snapshot(state, dimensions)
	if not state.get("pieces") is Array or pieces.size() != state.pieces.size(): return _fail("无效棋盘快照")
	current_state = state.duplicate(true)
	view.rebuild(pieces)
	var marked: Dictionary[int, bool] = {}
	for instance: Dictionary in state.get("instances", []): marked[String(instance.id).to_int()] = true
	for piece: PieceState in pieces:
		if marked.has(piece.piece_id):
			var marker: String = "行" if piece.content_id == LineClearState.CONTENT_ROW else ("列" if piece.content_id == LineClearState.CONTENT_COLUMN else ("爆" if piece.content_id == &"special_demolition" else "引"))
			view.show_ability_marker(piece.piece_id, marker)
	status.text = "结果观看 · seq=%d · 得分 %s · 移动 %s · 已选技能 %s" % [cursor, state.get("total", "?"), state.get("moves", "?"), state.get("consumed", "?")]
	return true

func _load_path() -> void:
	load_record(path_input.text)

func _tick() -> void:
	if play.button_pressed and not busy: step()

func _speed_selected(index: int) -> void:
	view.presentation_speed = [1.0, 4.0, 16.0][index]
	clock.wait_time = 0.3 / view.presentation_speed

func _fail(message: String) -> bool:
	error = message
	busy = false
	records.clear()
	status.text = "无法观看：" + message
	play.button_pressed = false
	return false
