class_name BoardRules
extends RefCounted

## 棋盘唯一变更入口。路径与连线只依赖数据，不查找节点或使用随机数。
const MOVE_DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MATCH_DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1)]

var state: BoardState
var minimum_match_count: int

func _init(board_state: BoardState, match_count: int) -> void:
	assert(board_state != null and match_count >= 2)
	state = board_state
	minimum_match_count = match_count

#region 棋盘变更
func place_piece(coordinate: Vector2i, match_color: int, content_id: StringName = &"", is_ghost: bool = false) -> PieceState:
	if not state.is_valid_coordinate(coordinate) or state.get_piece_id(coordinate) != 0 or match_color < 0:
		return null
	return state._insert(coordinate, match_color, content_id, is_ghost)

func set_piece_color(piece_id: int, match_color: int) -> bool:
	if state.get_piece(piece_id) == null or match_color < 0:
		return false
	state._set_color(piece_id, match_color)
	return true

func remove_piece(piece_id: int) -> PieceState:
	if state.get_piece(piece_id) == null:
		return null
	return state._remove(piece_id)

func move_piece(piece_id: int, target: Vector2i) -> BoardMoveResult:
	var result: BoardMoveResult = validate_move(piece_id, target)
	if result.is_valid():
		state._move(piece_id, target)
	return result
#endregion

#region 移动校验与四邻域路径
func validate_move(piece_id: int, target: Vector2i) -> BoardMoveResult:
	var result: BoardMoveResult = BoardMoveResult.new()
	result.piece_id = piece_id
	var piece: PieceState = state.get_piece(piece_id)
	if piece == null:
		result.failure = BoardMoveResult.Failure.INVALID_PIECE
	elif not state.is_valid_coordinate(target):
		result.failure = BoardMoveResult.Failure.OUT_OF_BOUNDS
	elif piece.coordinate == target:
		result.failure = BoardMoveResult.Failure.SAME_CELL
	elif state.get_piece_id(target) != 0:
		result.failure = BoardMoveResult.Failure.TARGET_OCCUPIED
	else:
		result.path = _find_path(piece.coordinate, target)
		if result.path.is_empty():
			result.failure = BoardMoveResult.Failure.NO_PATH
	return result

func _find_path(origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	# 棋盘规模较小，BFS直接读取权威占格，不维护第二份障碍缓存。
	var queue: Array[Vector2i] = [origin]
	var previous: Dictionary[Vector2i, Vector2i] = {origin: origin}
	var index: int = 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		if current == target:
			var path: Array[Vector2i] = [target]
			while path.back() != origin:
				path.append(previous[path.back()])
			path.reverse()
			return path
		for direction: Vector2i in MOVE_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if not state.is_valid_coordinate(neighbor) or previous.has(neighbor) or state.get_piece_id(neighbor) != 0:
				continue
			previous[neighbor] = current
			queue.append(neighbor)
	return []
#endregion

#region 四方向连线分组
func find_matches() -> Array[BoardMatchGroup]:
	var groups: Array[BoardMatchGroup] = []
	for piece: PieceState in state.get_snapshot():
		for direction: Vector2i in MATCH_DIRECTIONS:
			var previous: PieceState = state.get_piece_at(piece.coordinate - direction)
			if previous != null and previous.match_color == piece.match_color:
				continue
			var line: Array[int] = []
			var coordinate: Vector2i = piece.coordinate
			var current: PieceState = state.get_piece_at(coordinate)
			while current != null and current.match_color == piece.match_color:
				line.append(current.piece_id)
				coordinate += direction
				current = state.get_piece_at(coordinate)
			if line.size() >= minimum_match_count:
				_merge_line(groups, line)
	groups.sort_custom(func(a: BoardMatchGroup, b: BoardMatchGroup) -> bool: return a.piece_ids[0] < b.piece_ids[0])
	return groups

func find_matches_at(coordinate: Vector2i) -> Array[BoardMatchGroup]:
	var piece_id: int = state.get_piece_id(coordinate)
	var groups: Array[BoardMatchGroup] = []
	if piece_id == 0:
		return groups
	for group: BoardMatchGroup in find_matches():
		if group.piece_ids.has(piece_id):
			groups.append(group)
	return groups

func _merge_line(groups: Array[BoardMatchGroup], line: Array[int]) -> void:
	var merged: BoardMatchGroup = BoardMatchGroup.new()
	merged.piece_ids.assign(line)
	# 已有组彼此不相交，新线可以一次连接多个已有组。
	for index: int in range(groups.size() - 1, -1, -1):
		var intersects: bool = false
		for piece_id: int in groups[index].piece_ids:
			if line.has(piece_id):
				intersects = true
				break
		if intersects:
			for piece_id: int in groups[index].piece_ids:
				if not merged.piece_ids.has(piece_id):
					merged.piece_ids.append(piece_id)
			groups.remove_at(index)
	merged.piece_ids.sort()
	groups.append(merged)
#endregion
