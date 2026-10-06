class_name BoardView
extends Node2D

## 只保存实体ID到显示节点的映射；配置和快照由调用者显式传入。
const CELL_SCENE: PackedScene = preload("res://gameplay/board/cell/cell.tscn")
const PIECE_SCENE: PackedScene = preload("res://gameplay/board/piece/chess_piece.tscn")
const EXPLOSION_SCENE: PackedScene = preload("res://gameplay/presentation/explosion_visual/explosion_visual.tscn")

signal cell_pressed(coordinate: Vector2i)
signal presentation_changed

var _cells: Dictionary[Vector2i, Cell] = {}
var _pieces: Dictionary[int, ChessPiece] = {}
var _items: Dictionary[StringName, ItemData] = {}
var _generation: int = 0
var _spacing: Vector2
var _dimensions: Vector2i
var _cell_size: Vector2
var low_effects: bool = false
var _presentation_tweens: Array[Tween] = []
var presentation_speed: float = 1.0:
	set(value):
		presentation_speed = maxf(value, 0.01)
		for animation: Tween in _presentation_tweens:
			if animation.is_valid(): animation.set_speed_scale(presentation_speed)
var _playback_pending: bool = false

#region 显示初始化与查询
func _exit_tree() -> void:
	# 退出时仅取消任务；子节点由场景释放，不能先拆成游离节点。
	_generation += 1
	_playback_pending = false
	for animation: Tween in _presentation_tweens:
		if animation.is_valid(): animation.kill()
	_presentation_tweens.clear()
	for piece: ChessPiece in _pieces.values():
		if is_instance_valid(piece): piece.cancel_movement()
	presentation_changed.emit()

func configure(columns: int, rows: int, cell_size: Vector2, gap: Vector2) -> void:
	clear_display()
	_spacing = cell_size + gap
	_cell_size = cell_size
	_dimensions = Vector2i(columns, rows)
	for cell: Cell in _cells.values():
		remove_child(cell)
		cell.queue_free()
	_cells.clear()
	for x: int in range(columns):
		for y: int in range(rows):
			var cell: Cell = CELL_SCENE.instantiate() as Cell
			cell.coordinate = Vector2i(x, y)
			cell.low_effects = low_effects
			cell.position = Vector2(x, y) * (cell_size + gap)
			cell.pressed.connect(_on_cell_pressed)
			add_child(cell)
			_cells[cell.coordinate] = cell

func get_cell(coordinate: Vector2i) -> Cell:
	return _cells.get(coordinate)

## 格子以中心为原点，边框也计入布局；不用节点原点充当棋盘左上角。
func get_display_rect() -> Rect2:
	if _dimensions.x <= 0 or _dimensions.y <= 0: return Rect2()
	return Rect2(-_cell_size * 0.5, Vector2(_dimensions - Vector2i.ONE) * _spacing + _cell_size).grow(2.0)

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	for cell: Cell in _cells.values(): cell.set_low_effects(enabled)
	for piece: ChessPiece in _pieces.values(): piece.set_low_effects(enabled)
	for child: Node in get_children():
		if child is ExplosionVisual: (child as ExplosionVisual).set_low_effects(enabled)

func get_piece(piece_id: int) -> ChessPiece:
	return _pieces.get(piece_id)

func get_cells() -> Array[Cell]:
	var cells: Array[Cell] = []
	cells.assign(_cells.values())
	return cells

func clear_display() -> void:
	_generation += 1
	_playback_pending = false
	for animation: Tween in _presentation_tweens:
		if animation.is_valid(): animation.kill()
	_presentation_tweens.clear()
	for child: Node in get_children():
		if child is ExplosionVisual:
			remove_child(child)
			child.queue_free()
	for piece: ChessPiece in _pieces.values():
		if is_instance_valid(piece):
			piece.cancel_movement()
			piece.get_parent().remove_child(piece)
			piece.queue_free()
	_pieces.clear()
	# 消除中的棋子已从ID映射注销，仍需在重试时清理。
	for child: Node in get_children():
		if child is ChessPiece:
			remove_child(child)
			child.queue_free()
	for cell: Cell in _cells.values():
		cell.unhighlight()
	presentation_changed.emit()

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
	piece.low_effects = low_effects
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

func show_ability_marker(piece_id: int, text: String) -> void:
	var piece: ChessPiece = get_piece(piece_id)
	if is_instance_valid(piece):
		piece.set_ability_marker(text)

func show_blast(center: Vector2i, radius: int) -> void:
	if radius < 0 or not _cells.has(center):
		return
	var visual: ExplosionVisual = EXPLOSION_SCENE.instantiate() as ExplosionVisual
	visual.low_effects = low_effects
	add_child(visual)
	visual.position = Vector2(center) * _spacing
	var minimum: Vector2i = Vector2i(maxi(0, center.x - radius), maxi(0, center.y - radius))
	var maximum: Vector2i = Vector2i(mini(center.x + radius, _dimensions.x - 1), mini(center.y + radius, _dimensions.y - 1))
	var corner: Vector2 = Vector2(minimum - center) * _spacing - _spacing * 0.5
	var size: Vector2 = Vector2(maximum - minimum + Vector2i.ONE) * _spacing
	track_presentation(visual.setup(Rect2(corner, size)))
#endregion

#region 结果演出
func animate_move(result: BoardMoveResult, duration: float) -> bool:
	var generation: int = _generation
	var piece: ChessPiece = get_piece(result.piece_id)
	if not result.is_valid() or result.path.is_empty() or not is_instance_valid(piece): return false
	for coordinate: Vector2i in result.path:
		if get_cell(coordinate) == null: return false
	var source: Cell = get_cell(result.path[0])
	if source.piece != piece: return false
	source.take_piece()
	piece.position = source.position
	add_child(piece)
	for coordinate: Vector2i in result.path:
		get_cell(coordinate).highlight_path()
	for coordinate: Vector2i in result.path:
		piece.move_to_and_wait(get_cell(coordinate), maxf(duration / result.path.size(), 0.001))
		track_presentation(piece.tween)
		await piece.movement_completed
		if generation != _generation:
			return false
	remove_child(piece)
	get_cell(result.path.back()).show_piece(piece)
	piece.position = Vector2.ZERO
	for coordinate: Vector2i in result.path:
		get_cell(coordinate).unhighlight()
	return true

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
		piece.eliminate()
		track_presentation(piece.tween)
		await piece.tween.finished
	piece.queue_free()

## 记录本视图实际启动的演出；等待不重新计算或修改规则结果。
func track_presentation(animation: Tween) -> void:
	animation.set_speed_scale(maxf(presentation_speed, 0.01))
	_presentation_tweens.append(animation)
	animation.finished.connect(_on_animation_finished)

func is_presenting() -> bool:
	return _playback_pending or _animations_running()

func set_playback_pending(value: bool) -> void:
	_playback_pending = value
	presentation_changed.emit()

func _on_animation_finished() -> void:
	presentation_changed.emit()

func _animations_running() -> bool:
	for index: int in range(_presentation_tweens.size() - 1, -1, -1):
		var animation: Tween = _presentation_tweens[index]
		if not animation.is_valid() or not animation.is_running():
			_presentation_tweens.remove_at(index)
	return not _presentation_tweens.is_empty()

func animate_spawn(snapshot: PieceState, duration: float) -> void:
	var piece: ChessPiece = PIECE_SCENE.instantiate() as ChessPiece
	show_piece(snapshot, piece)
	piece.scale = Vector2.ZERO
	var animation: Tween = piece.create_tween()
	animation.tween_property(piece, "scale", Vector2.ONE, maxf(0.0, duration))
	track_presentation(animation)

## 导演每步只等待实际动画；队列状态由父级另行映射给公开查询。
func wait_for_animations() -> bool:
	var generation: int = _generation
	while _animations_running():
		await presentation_changed
		if generation != _generation: return false
	return true

func wait_for_presentation() -> bool:
	var generation: int = _generation
	while is_presenting():
		await presentation_changed
		if generation != _generation: return false
	return true

func _on_cell_pressed(cell: Cell) -> void:
	cell_pressed.emit(cell.coordinate)
#endregion
