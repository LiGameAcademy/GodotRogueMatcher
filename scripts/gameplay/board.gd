extends Node2D
class_name Board

## M1兼容协调器：旧回合流程调用规则入口，表现由独立BoardView消费。
signal initialized

@export var rows: int = 9
@export var cols: int = 9
@export var grid_gap: Vector2 = Vector2(1, 1)
var cell_size: Vector2 = Vector2(64, 64)
var rules: BoardRules
var can_selected: bool = false
var _generation: int = 0
var selected_piece: ChessPiece = null:
	set(value):
		if is_instance_valid(selected_piece):
			selected_piece.deselected()
		selected_piece = value
		if is_instance_valid(selected_piece):
			selected_piece.selected()

@onready var view: BoardView = $BoardView

func _ready() -> void:
	add_to_group("board")
	view.cell_pressed.connect(_on_coordinate_pressed)

#region 初始化与重试
## 规则对象由Game显式注入，重试传入全新的状态。
func start_game(board_rules: BoardRules) -> void:
	_generation += 1
	var generation: int = _generation
	can_selected = false
	selected_piece = null
	rules = board_rules
	view.configure(cols, rows, cell_size, grid_gap)
	GameManager.reset_game()
	await get_tree().process_frame
	await SpawnManager.spawn_random_pieces(self)
	if generation != _generation:
		return
	GameManager.start_turn()
	can_selected = not GameManager.is_game_over
	initialized.emit()

func retry_game(board_rules: BoardRules) -> void:
	get_tree().paused = false
	ItemEffectSystem.placed_items.clear()
	LevelUpSystem.reset_system()
	ItemRegistry.register_all_items()
	await start_game(board_rules)
#endregion

#region 单一棋盘写入口与显示适配
func place_piece(coordinate: Vector2i, piece: ChessPiece) -> bool:
	var content_id: StringName = StringName(piece.item_data.id) if piece.item_data != null else &""
	var snapshot: PieceState = rules.place_piece(coordinate, piece.piece_type, content_id, piece.is_ghost)
	if snapshot == null:
		return false
	view.show_piece(snapshot, piece)
	_update_count_display()
	return true

func remove_piece(coordinate: Vector2i, animated: bool = false) -> bool:
	var piece_id: int = rules.state.get_piece_id(coordinate)
	var snapshot: PieceState = rules.remove_piece(piece_id)
	if snapshot == null:
		return false
	var piece: ChessPiece = view.get_piece(piece_id)
	if selected_piece == piece:
		selected_piece = null
	if is_instance_valid(piece) and piece.item_data != null:
		ItemEffectSystem.unregister_item(piece)
	view.remove_piece(snapshot, animated)
	_update_count_display()
	return true

func set_piece_color(coordinate: Vector2i, match_color: int) -> bool:
	var piece_id: int = rules.state.get_piece_id(coordinate)
	if not rules.set_piece_color(piece_id, match_color):
		return false
	view.show_color(piece_id, match_color)
	return true

func rebuild_view() -> void:
	selected_piece = null
	view.rebuild(rules.state.get_snapshot())
	# 重建不是获得道具，不重新触发ON_PLACE。
	ItemEffectSystem.placed_items.clear()
	for snapshot: PieceState in rules.state.get_snapshot():
		if not snapshot.content_id.is_empty():
			ItemEffectSystem.placed_items.append(view.get_piece(snapshot.piece_id))

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

func move_selected_piece(target_cell: Cell, duration: float = 0.5) -> bool:
	if not can_selected or GameManager.is_game_over or not is_instance_valid(selected_piece) or target_cell == null:
		return false
	var result: BoardMoveResult = rules.move_piece(selected_piece.piece_id, target_cell.coordinate)
	if not result.is_valid():
		selected_piece = null
		return false
	var generation: int = _generation
	can_selected = false
	# 移动已经提交，演出只使用路径结果，不决定是否合法。
	await view.animate_move(result, duration)
	if generation != _generation:
		return false
	selected_piece = null
	await MatchSystem.check_and_eliminate(self, target_cell)
	if generation != _generation:
		return false
	await LevelUpSystem.resolve_pending_rewards(self)
	if generation != _generation or GameManager.is_game_over:
		return true
	GameManager.end_turn()
	await LevelUpSystem.resolve_pending_rewards(self)
	if generation != _generation or GameManager.is_game_over:
		return true
	# M2迁移前保留旧Demo的计分与补棋规则。
	var should_spawn: bool = not GameManager.score_earned_this_turn or is_board_empty()
	if should_spawn:
		await get_tree().create_timer(0.5).timeout
		if generation != _generation:
			return false
		await SpawnManager.spawn_random_pieces(self)
		if generation != _generation:
			return false
	if not GameManager.is_game_over:
		await LevelUpSystem.resolve_pending_rewards(self)
		if generation != _generation:
			return false
		if not GameManager.is_game_over:
			GameManager.start_turn()
	can_selected = not GameManager.is_game_over
	return true

func _on_coordinate_pressed(coordinate: Vector2i) -> void:
	if not can_selected or GameManager.is_game_over:
		return
	var piece_id: int = rules.state.get_piece_id(coordinate)
	if piece_id != 0:
		selected_piece = view.get_piece(piece_id)
	elif is_instance_valid(selected_piece):
		await move_selected_piece(get_cell(coordinate))

func _update_count_display() -> void:
	# 旧HUD兼容字段是派生显示值，不能用于占格或寻路决策。
	GameManager.piece_count = rules.state.get_piece_count()
#endregion
