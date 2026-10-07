class_name BoardInputBuffer
extends RefCounted

## 只保存下一次输入意图；不提交规则或调度回合。
var started_ms: int = 0
var piece_id: int = 0
var coordinate: Vector2i = Vector2i(-1, -1)
var target: Vector2i = Vector2i(-1, -1)

func cancel(view: BoardView, observation: BoardObservation, reason: String) -> void:
	observation.cancel_buffer(reason)
	if is_instance_valid(view):
		var cell: Cell = view.get_cell(coordinate)
		if cell != null: cell.unhighlight()
	piece_id = 0
	coordinate = Vector2i(-1, -1)
	target = Vector2i(-1, -1)

func receive(clicked: Vector2i, view: BoardView, state: BoardState, observation: BoardObservation) -> String:
	var cell: Cell = view.get_cell(clicked)
	if cell == null: return ""
	if is_instance_valid(cell.piece):
		var id: int = cell.piece.piece_id
		if state.get_piece(id) == null: return ""
		cancel(view, observation, "overwritten")
		observation.buffered_input = observation.input("move", true)
		started_ms = Time.get_ticks_msec()
		piece_id = id
		coordinate = clicked
		cell.highlight_path()
		return "下一枚棋子已暂存"
	elif piece_id != 0:
		if target != Vector2i(-1, -1):
			observation.cancel_buffer("overwritten")
			observation.buffered_input = observation.input("move", true)
		target = clicked
		return "下一步移动已暂存，结算后验证"
	return ""
