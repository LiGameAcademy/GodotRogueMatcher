class_name BoardRules
extends RefCounted

## 棋盘唯一变更入口。路径与连线只依赖数据，不查找节点或使用随机数。
const MOVE_DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MATCH_DIRECTIONS: Array[Vector2i] = BoardMatchDetector.LINE_DIRECTIONS

var state: BoardState
var minimum_match_count: int
var _match_templates: Array[MatchShapeTemplate] = []

func _init(board_state: BoardState, match_count: int, templates: Array[MatchShapeTemplate] = []) -> void:
	assert(board_state != null and match_count >= 2)
	state = board_state
	minimum_match_count = match_count
	assert(BoardMatchDetector.validation_error(templates).is_empty())
	for template: MatchShapeTemplate in templates:
		_match_templates.append(template.duplicate(true) as MatchShapeTemplate)

## Construction-only prototype configuration, detached from callers and shared Resources.
func match_templates() -> Array[MatchShapeTemplate]:
	var result: Array[MatchShapeTemplate] = []
	for template: MatchShapeTemplate in _match_templates:
		result.append(template.duplicate(true) as MatchShapeTemplate)
	return result

func template_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for template: MatchShapeTemplate in _match_templates:
		result.append({"shape_id": String(template.shape_id), "offsets": template.offsets.duplicate()})
	return result

## Budget previews use the same enabled rules, without sharing occupancy or mutable templates.
func placement_preview() -> BoardRules:
	var result: BoardRules = BoardRules.new(BoardState.new(state.columns, state.rows), minimum_match_count, _match_templates)
	for piece: PieceState in state.get_snapshot():
		result.place_piece(piece.coordinate, piece.match_color, piece.content_id, piece.is_ghost)
	return result

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

func set_piece_content(piece_id: int, content_id: StringName) -> bool:
	if state.get_piece(piece_id) == null:
		return false
	state._set_content(piece_id, content_id)
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

#region 统一命中查询
func find_matches() -> Array[BoardMatchGroup]:
	return BoardMatchDetector.find_matches(state, minimum_match_count, _match_templates)

func find_matches_at(coordinate: Vector2i) -> Array[BoardMatchGroup]:
	return BoardMatchDetector.find_matches_at(state, minimum_match_count, coordinate, _match_templates)
#endregion
