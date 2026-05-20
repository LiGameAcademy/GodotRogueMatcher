extends Node2D
class_name Board

## 棋盘管理器
## 职责：管理棋盘本身（单元格创建、布局、选中、移动）

var s_cell: PackedScene = preload("res://prefabs/cell.tscn")

@export var rows: int = 9
@export var cols: int = 9
@export var grid_gap: Vector2 = Vector2(1, 1)
var cell_size: Vector2 = Vector2(64, 64)

## 当前选中的棋子，默认为空
var selected_piece: ChessPiece = null:
	set(value):
		if selected_piece:
			selected_piece.deselected()
		if value:
			value.selected()
		selected_piece = value

var can_selected: bool = true

func _ready() -> void:
	# 添加到组中，方便其他系统查找
	add_to_group("board")
	
	# 确保单例已加载
	if not PathfindingManager:
		push_error("PathfindingManager 单例未加载！")
		return
	if not SpawnManager:
		push_error("SpawnManager 单例未加载！")
		return
	if not GameManager:
		push_error("GameManager 单例未加载！")
		return
	
	# 初始化寻路系统
	PathfindingManager.initialize(rows, cols)
	
	# 初始化棋盘
	initialize_board()
	
	# 重置游戏状态（确保初始状态正确）
	GameManager.reset_game()
	
	# 生成初始棋子
	await get_tree().process_frame
	var spawned = SpawnManager.spawn_random_pieces(self)
	print("Board 初始化完成，生成了 ", spawned, " 个棋子")
	
	# 开始第一回合
	GameManager.start_turn()

## 初始化我们的棋盘
func initialize_board() -> void:
	for i in cols:
		for j in rows:
			var grid_cell: Cell = s_cell.instantiate()
			grid_cell.coordinate = Vector2i(i, j)
			grid_cell.position = Vector2(i * (cell_size.x + grid_gap.x), j * (cell_size.y + grid_gap.y))
			
			# 将网格点击事件绑定到相应方法
			grid_cell.pressed.connect(_on_cell_pressed)
			
			# 当棋盘网格的棋子状态发生改变时候，更新AStarGrid2D对象的障碍物信息
			grid_cell.piece_changed.connect(
				func(cell: Cell, piece: ChessPiece) -> void:
					PathfindingManager.update_obstacle(cell.coordinate, piece != null)
			)
			
			self.add_child(grid_cell)

## 重试游戏
func retry_game() -> void:
	# 清空所有棋子
	for cell in self.get_children():
		if cell is Cell:
			cell.piece = null
	
	# 重置游戏状态
	GameManager.reset_game()
	
	# 重新初始化寻路系统
	PathfindingManager.initialize(rows, cols)
	
	# 生成初始棋子
	SpawnManager.spawn_random_pieces(self)
	
	get_tree().paused = false

## 根据坐标获取网格
func get_cell(coordinate: Vector2i) -> Cell:
	var grid_index: int = coordinate.x * cols + coordinate.y
	var cell: Cell = self.get_child(grid_index)
	return cell

## 检查棋盘是否为空（没有任何棋子）
## [return: bool] 如果棋盘为空返回 true
func is_board_empty() -> bool:
	for cell in get_children():
		if cell is Cell:
			if cell.piece != null:
				return false
	return true

## 根据坐标集合获取多个棋盘网格
func get_cells(coords: Array) -> Array[Cell]:
	var cells: Array[Cell]
	for c in coords:
		cells.append(get_cell(c))
	return cells

## 判断坐标位置是否存在棋子
func has_piece(coordinate: Vector2i) -> bool:
	var cell = get_cell(coordinate)
	return cell.piece != null

## 网格点击事件处理函数
func _on_cell_pressed(cell: Cell) -> void:
	if not can_selected:
		return
	
	# 判断点击网格是否有棋子？
	if cell.piece != null:
		# 有:将其存为选中棋子
		selected_piece = cell.piece
	elif selected_piece != null:
		# 没有: 判断当前是否选中了棋子？
		# 有：执行移动逻辑（移动、消除、生成逻辑都在 move_selected_piece 中处理）
		await move_selected_piece(cell)

## 移动棋子（非阻塞）
func move_selected_piece(target_cell: Cell, duration: float = 0.5) -> bool:
	can_selected = false
	var selected_cell: Cell = selected_piece.get_parent()

	# 获取导航路径（坐标点集合）
	var path_array: PackedVector2Array = PathfindingManager.get_chess_path(selected_cell.coordinate, target_cell.coordinate)
	# 转换为 Vector2i 数组
	var path: Array = []
	for vec in path_array:
		path.append(Vector2i(vec))
	var path_cells: Array = get_cells(path)

	if not path.is_empty():
		# 导航路径不为空，代表有路径
		# 高亮路径
		for c in path_cells:
			c.highlight_path()

		# 移除棋子
		selected_cell.piece = null
		selected_piece.position = selected_cell.position
		self.add_child(selected_piece)

		var move_duration = duration / path.size()

		# 启动所有移动动画（非阻塞）
		var pending_moves = path.size()
		for p in path:
			var cell = get_cell(p)
			selected_piece.move_to(cell, move_duration)
		# 等待所有移动完成
		await _wait_all_moves(pending_moves)

		# 放置棋子
		self.remove_child(selected_piece)
		target_cell.piece = selected_piece
		selected_piece.position = Vector2.ZERO

		# 取消高亮
		for c in path_cells:
			c.unhighlight()

		# 检查消除
		await MatchSystem.check_and_eliminate(self, target_cell)

		# 移动完成，结束回合
		GameManager.end_turn()

		# 核心机制：如果创造了得分就不产生新的棋子（除非棋盘空了）
		var should_spawn: bool = false
		if not GameManager.score_earned_this_turn:
			# 没有得分，正常生成新棋子
			should_spawn = true
		elif is_board_empty():
			# 有得分但棋盘为空，必须生成新棋子
			should_spawn = true
			print("棋盘为空，强制生成新棋子")
		else:
			# 有得分且棋盘不为空，不生成新棋子
			print("本轮产生了得分，不生成新棋子")

		if should_spawn:
			await get_tree().create_timer(0.5).timeout
			SpawnManager.spawn_random_pieces(self)

		# 生成完成后开始新回合
		GameManager.start_turn()

	selected_piece = null
	can_selected = true
	return not path.is_empty()

## 等待所有移动动画完成（非阻塞）
func _wait_all_moves(pending_count: int) -> void:
	if pending_count <= 0 or not is_instance_valid(selected_piece):
		return

	var counter = [{"count": 0}]

	var on_move_done = func() -> void:
		counter[0]["count"] += 1

	selected_piece.movement_completed.connect(on_move_done)

	# 轮询等待完成
	while counter[0]["count"] < pending_count and is_instance_valid(selected_piece):
		await get_tree().process_frame

	if is_instance_valid(selected_piece):
		selected_piece.movement_completed.disconnect(on_move_done)
