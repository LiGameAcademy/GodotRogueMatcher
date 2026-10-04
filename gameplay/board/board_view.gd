class_name BoardView
extends Node2D

## 只保存实体ID到显示节点的映射；配置和快照由调用者显式传入。
const CELL_SCENE: PackedScene = preload("res://prefabs/cell.tscn")
const PIECE_SCENE: PackedScene = preload("res://prefabs/chess_piece.tscn")

signal cell_pressed(coordinate: Vector2i)

var _cells: Dictionary[Vector2i, Cell] = {}
var _pieces: Dictionary[int, ChessPiece] = {}
var _items: Dictionary[StringName, ItemData] = {}
var _generation: int = 0

#region 显示初始化与查询
func configure(columns: int, rows: int, cell_size: Vector2, gap: Vector2) -> void:
	clear_display()
	for cell: Cell in _cells.values():
		remove_child(cell)
		cell.queue_free()
	_cells.clear()
	for x: int in range(columns):
		for y: int in range(rows):
			var cell: Cell = CELL_SCENE.instantiate() as Cell
			cell.coordinate = Vector2i(x, y)
			cell.position = Vector2(x, y) * (cell_size + gap)
			cell.pressed.connect(_on_cell_pressed)
			add_child(cell)
			_cells[cell.coordinate] = cell

func get_cell(coordinate: Vector2i) -> Cell:
	return _cells.get(coordinate)

func get_piece(piece_id: int) -> ChessPiece:
	return _pieces.get(piece_id)

func get_cells() -> Array[Cell]:
	var cells: Array[Cell] = []
	cells.assign(_cells.values())
	return cells

func clear_display() -> void:
	_generation += 1
	for piece: ChessPiece in _pieces.values():
		if is_instance_valid(piece):
			piece.cancel_movement()
			piece.get_parent().remove_child(piece)
			piece.queue_free()
	_pieces.clear()
	for cell: Cell in _cells.values():
		cell.unhighlight()

## 重建只消费快照，不改变规则或棋子ID。
func rebuild(snapshot: Array[PieceState]) -> void:
	clear_display()
	for piece_state: PieceState in snapshot:
		var piece: ChessPiece = PIECE_SCENE.instantiate() as ChessPiece
		if not piece_state.content_id.is_empty():
			var item: ItemData = _items.get(piece_state.content_id)
			if item != null:
				piece.initialize_item(item)
		show_piece(piece_state, piece)

func show_piece(piece_state: PieceState, piece: ChessPiece) -> void:
	var cell: Cell = get_cell(piece_state.coordinate)
	assert(cell != null and cell.piece == null)
	piece.piece_id = piece_state.piece_id
	cell.show_piece(piece)
	piece.position = Vector2.ZERO
	piece.piece_type = piece_state.match_color
	piece.is_ghost = piece_state.is_ghost
	piece.modulate.a = 0.5 if piece_state.is_ghost else 1.0
	_pieces[piece.piece_id] = piece
	if piece.item_data != null:
		_items[piece_state.content_id] = piece.item_data

func show_color(piece_id: int, match_color: int) -> void:
	var piece: ChessPiece = get_piece(piece_id)
	if is_instance_valid(piece):
		piece.piece_type = match_color
#endregion

#region 结果演出
func animate_move(result: BoardMoveResult, duration: float) -> void:
	var generation: int = _generation
	var piece: ChessPiece = get_piece(result.piece_id)
	var source: Cell = get_cell(result.path[0])
	source.take_piece()
	piece.position = source.position
	add_child(piece)
	for coordinate: Vector2i in result.path:
		get_cell(coordinate).highlight_path()
	for coordinate: Vector2i in result.path:
		piece.move_to_and_wait(get_cell(coordinate), maxf(duration / result.path.size(), 0.001))
		await piece.movement_completed
		if generation != _generation:
			return
	remove_child(piece)
	get_cell(result.path.back()).show_piece(piece)
	piece.position = Vector2.ZERO
	for coordinate: Vector2i in result.path:
		get_cell(coordinate).unhighlight()

func remove_piece(piece_state: PieceState, animated: bool = false) -> void:
	var piece: ChessPiece = get_piece(piece_state.piece_id)
	if not is_instance_valid(piece):
		return
	_pieces.erase(piece_state.piece_id)
	var cell: Cell = get_cell(piece_state.coordinate)
	cell.take_piece()
	if animated:
		piece.position = cell.position
		add_child(piece)
		await piece.eliminate()
	piece.queue_free()

func _on_cell_pressed(cell: Cell) -> void:
	cell_pressed.emit(cell.coordinate)
#endregion
