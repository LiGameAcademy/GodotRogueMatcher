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
	var spawned = SpawnManager.spawn_random_pieces(self)
	print("Board 初始化完成，生成了 ", spawned, " 个棋子")

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
		# 有：执行移动逻辑
		var can_move = await move_selected_piece(cell)
		if can_move:
			# 检查消除
			await MatchSystem.check_and_eliminate(self, cell)
			# 生成新棋子
			SpawnManager.spawn_random_pieces(self)

## 移动棋子
func move_selected_piece(target_cell: Cell) -> bool:
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
		
		# 移动动画
		for p in path:
			await selected_piece.move_to(get_cell(p))
		
		# 放置棋子
		self.remove_child(selected_piece)
		target_cell.piece = selected_piece
		selected_piece.position = Vector2.ZERO
		
		# 取消高亮
		for c in path_cells:
			c.unhighlight()
	
	selected_piece = null
	can_selected = true
	return not path.is_empty()
