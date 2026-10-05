class_name BoardState
extends RefCounted

## 唯一占格状态。外部只读取快照，变更由 BoardRules 提交。
var columns: int
var rows: int
var _next_piece_id: int = 1
var _pieces: Dictionary[int, PieceState] = {}
var _occupancy: Dictionary[Vector2i, int] = {}

func _init(column_count: int, row_count: int) -> void:
	assert(column_count > 0 and row_count > 0, "棋盘尺寸必须为正数")
	columns = column_count
	rows = row_count

#region 查询与快照
func is_valid_coordinate(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.x < columns and coordinate.y >= 0 and coordinate.y < rows

func get_piece_id(coordinate: Vector2i) -> int:
	return _occupancy.get(coordinate, 0)

func get_piece(piece_id: int) -> PieceState:
	var piece: PieceState = _pieces.get(piece_id)
	return piece.copy() if piece != null else null

func get_piece_at(coordinate: Vector2i) -> PieceState:
	return get_piece(get_piece_id(coordinate))

func get_piece_count() -> int:
	return _pieces.size()

func next_piece_id() -> int:
	return _next_piece_id

func get_empty_coordinates() -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []
	for x: int in range(columns):
		for y: int in range(rows):
			var coordinate: Vector2i = Vector2i(x, y)
			if get_piece_id(coordinate) == 0:
				coordinates.append(coordinate)
	return coordinates

func get_snapshot() -> Array[PieceState]:
	var pieces: Array[PieceState] = []
	var ids: Array[int] = []
	ids.assign(_pieces.keys())
	ids.sort()
	for piece_id: int in ids:
		pieces.append(_pieces[piece_id].copy())
	return pieces
#endregion

#region 规则提交内部接口
func _insert(coordinate: Vector2i, match_color: int, content_id: StringName, is_ghost: bool) -> PieceState:
	var piece: PieceState = PieceState.new()
	piece.piece_id = _next_piece_id
	_next_piece_id += 1
	piece.coordinate = coordinate
	piece.match_color = match_color
	piece.content_id = content_id
	piece.is_ghost = is_ghost
	_pieces[piece.piece_id] = piece
	_occupancy[coordinate] = piece.piece_id
	return piece.copy()

func _move(piece_id: int, coordinate: Vector2i) -> void:
	var piece: PieceState = _pieces[piece_id]
	_occupancy.erase(piece.coordinate)
	piece.coordinate = coordinate
	_occupancy[coordinate] = piece_id

func _set_color(piece_id: int, match_color: int) -> void:
	_pieces[piece_id].match_color = match_color

func _remove(piece_id: int) -> PieceState:
	var piece: PieceState = _pieces[piece_id]
	_occupancy.erase(piece.coordinate)
	_pieces.erase(piece_id)
	return piece.copy()
#endregion
