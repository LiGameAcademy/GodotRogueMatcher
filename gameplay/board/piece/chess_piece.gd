extends Node2D
class_name ChessPiece

## 棋子颜色配置（赛博霓虹色）
## 色盲友好设计：每种颜色对应唯一形状
const PIECE_COLORS: Array[Color] = [
	Color("#ff0000"),  # 红色 - 圆形
	Color("#00ff00"),  # 绿色 - 方形
	Color("#0000ff"),  # 蓝色 - 三角形
	Color("#ffff00"),  # 黄色 - 五边形
	Color("#ff00ff"),  # 紫色 - 星形
]

## 棋子形状枚举（色盲友好：颜色和形状一一对应）
enum ShapeType {
	CIRCLE = 0,      # 圆形 - 红色
	SQUARE = 1,      # 方形 - 绿色
	TRIANGLE = 2,    # 三角形 - 蓝色
	PENTAGON = 3,    # 五边形 - 黄色
	STAR = 4         # 星形 - 紫色
}

## 显示模式枚举
enum DisplayMode {
	SHAPE,  # 显示形状（普通棋子）
	ICON    # 显示图标（道具）
}

## 节点引用
@onready var polygon: Polygon2D = $Polygon2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var glow_particles: GPUParticles2D = $GlowParticles
@onready var ability_marker: Label = $AbilityMarker

## 显示模式
var display_mode: DisplayMode = DisplayMode.SHAPE
## 显示映射ID，规则数据由BoardState持有。
var piece_id: int = 0

## 棋子类型（0-4，对应5种颜色，仅用于 SHAPE 模式）
var piece_type: int = 0 :
	set(value):
		piece_type = value
		if display_mode == DisplayMode.SHAPE:
			update_visual()

## 物品数据（用于 ICON 模式，道具视为特殊棋子）
var item_data: ItemData = null :
	set(value):
		item_data = value
		if value:
			display_mode = DisplayMode.ICON
			update_visual()
		else:
			display_mode = DisplayMode.SHAPE

var tween: Tween = null
var is_selected: bool = false
var low_effects: bool = false

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	if glow_particles:
		glow_particles.emitting = false
		glow_particles.visible = not enabled
	# 演出进行中不取消移动/离场Tween；只有静止选择的装饰可以重建。
	if is_selected and not _is_moving and not is_eliminating:
		is_selected = false
		selected()
var is_eliminating: bool = false
var is_ghost: bool = false  # 幽灵球标志（空间压缩机效果）
var _is_moving: bool = false

## 移动完成信号
signal movement_completed()

func _ready() -> void:
	update_visual()
	setup_glow_particles()

## 是否正在移动
func is_moving() -> bool:
	return _is_moving

## 标记由表现调用者根据本局能力映射传入。
func set_ability_marker(text: String) -> void:
	ability_marker.text = text
	ability_marker.visible = not text.is_empty()

## 重建显示或重试时取消旧演出，释放等待中的移动协程。
func cancel_movement() -> void:
	if _is_moving:
		if tween != null:
			tween.kill()
		_is_moving = false
		movement_completed.emit()

## 更新视觉效果
## 支持两种模式：形状（棋子）和图标（道具）
func update_visual() -> void:
	if not is_inside_tree():
		await ready
	
	match display_mode:
		DisplayMode.SHAPE:
			_update_shape_visual()
		DisplayMode.ICON:
			_update_icon_visual()

## 更新形状视觉（普通棋子）
func _update_shape_visual() -> void:
	# 隐藏图标，显示形状
	if sprite:
		sprite.visible = false
	if polygon:
		polygon.visible = true
		
		# 确保 piece_type 在有效范围内
		var type_index: int = piece_type % PIECE_COLORS.size()
		var color: Color = PIECE_COLORS[type_index]
		var shape_type: ShapeType = type_index as ShapeType  # 颜色和形状一一对应
		
		# 设置颜色
		polygon.color = color
		
		# 根据形状类型生成多边形（色盲友好：每种颜色唯一形状）
		match shape_type:
			ShapeType.CIRCLE:  # 红色 - 圆形
				polygon.polygon = generate_circle_polygon(15, 20)
			ShapeType.SQUARE:  # 绿色 - 方形
				polygon.polygon = generate_square_polygon(20)
			ShapeType.TRIANGLE:  # 蓝色 - 三角形
				polygon.polygon = generate_triangle_polygon(20)
			ShapeType.PENTAGON:  # 黄色 - 五边形
				polygon.polygon = generate_pentagon_polygon(20)
			ShapeType.STAR:  # 紫色 - 星形
				polygon.polygon = generate_star_polygon(20)
		
		# 更新辉光粒子颜色
		if glow_particles:
			update_particle_color(color)

## 生成圆形多边形
func generate_circle_polygon(radius: float, segments: int = 16) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = (i * TAU) / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

## 生成方形多边形
func generate_square_polygon(size: float) -> PackedVector2Array:
	var half: float = size * 0.707  # 对角线的一半
	return PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half)
	])

## 生成三角形多边形
func generate_triangle_polygon(size: float) -> PackedVector2Array:
	var height: float = size * 0.866  # 等边三角形高度
	return PackedVector2Array([
		Vector2(0, -size),
		Vector2(height, size * 0.5),
		Vector2(-height, size * 0.5)
	])

## 生成五边形多边形（色盲友好：黄色）
func generate_pentagon_polygon(size: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(5):
		var angle: float = (i * TAU / 5) - (TAU / 4)  # 从顶部开始，旋转90度
		points.append(Vector2(cos(angle), sin(angle)) * size)
	return points

## 生成星形多边形（色盲友好：紫色）
func generate_star_polygon(size: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_radius: float = size
	var inner_radius: float = size * 0.4  # 内圆半径
	for i: int in range(10):  # 5个外点 + 5个内点
		var angle: float = (i * TAU / 10) - (TAU / 4)  # 从顶部开始
		var radius: float = outer_radius if i % 2 == 0 else inner_radius
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

## 设置辉光粒子
func setup_glow_particles() -> void:
	if not glow_particles:
		return
	
	# 配置粒子系统
	glow_particles.amount = 20
	glow_particles.lifetime = 1.0
	glow_particles.emitting = false
	glow_particles.visible = not low_effects
	
	# 设置粒子材质
	var particle_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	particle_material.gravity = Vector3(0, 0, 0)
	particle_material.initial_velocity_min = 5.0
	particle_material.initial_velocity_max = 10.0
	particle_material.angular_velocity_min = -180.0
	particle_material.angular_velocity_max = 180.0
	glow_particles.process_material = particle_material

## 更新粒子颜色
func update_particle_color(color: Color) -> void:
	if not glow_particles:
		return
	
	var particle_material: ParticleProcessMaterial = glow_particles.process_material as ParticleProcessMaterial
	if particle_material:
		particle_material.color = color

## 选择动画效果
func selected() -> void:
	if is_selected:
		return
	
	is_selected = true
	if tween:
		tween.kill()
	
	tween = create_tween()
	if not low_effects: tween.set_loops()
	tween.set_trans(Tween.TRANS_CUBIC if low_effects else Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15)
	tween.tween_property(self, "scale", Vector2.ONE * (1.1 if low_effects else 1.0), 0.15)
	
	# 启动辉光粒子
	if glow_particles and not low_effects:
		glow_particles.emitting = true
		glow_particles.restart()

## 取消选择动画效果
func deselected() -> void:
	if not is_selected:
		return
	
	is_selected = false
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	# 停止辉光粒子
	if glow_particles:
		glow_particles.emitting = false

## 移动到目标格子（等待完成）
func move_to_and_wait(target_cell: Cell, duration: float = 0.15) -> void:
	if tween:
		tween.kill()

	_is_moving = true
	tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", target_cell.position, duration)
	tween.finished.connect(_on_move_completed)

## 消除动画
func eliminate() -> void:
	if is_eliminating:
		return
	
	is_eliminating = true
	
	# 爆炸粒子效果
	if glow_particles and not low_effects:
		glow_particles.emitting = true
		glow_particles.restart()
		var particle_material: ParticleProcessMaterial = glow_particles.process_material as ParticleProcessMaterial
		if particle_material:
			particle_material.initial_velocity_min = 20.0
			particle_material.initial_velocity_max = 50.0
	
	# 缩放和旋转动画
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.parallel().tween_property(self, "scale", Vector2.ZERO if low_effects else Vector2(1.5, 1.5), 0.2)
	if not low_effects: tween.parallel().tween_property(self, "rotation", rotation + TAU, 0.2)
	
	# 根据显示模式淡出对应的视觉元素
	if display_mode == DisplayMode.SHAPE and polygon:
		tween.parallel().tween_property(polygon, "modulate:a", 0.0, 0.2)
	elif display_mode == DisplayMode.ICON and sprite:
		tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.2)
	
	await tween.finished
	
	# 节点生命周期由棋盘清理入口负责；演出不自行释放占格对象。

## 重置状态
func reset() -> void:
	is_selected = false
	is_eliminating = false
	scale = Vector2.ONE
	rotation = 0.0
	if polygon:
		polygon.modulate.a = 1.0
	if sprite:
		sprite.modulate.a = 1.0
	if glow_particles:
		glow_particles.emitting = false

## 初始化物品（便捷方法，将道具视为特殊棋子）
## [param data: ItemData] 物品数据
func initialize_item(data: ItemData) -> void:
	item_data = data

## 出现动画（用于道具）
func spawn_animation() -> void:
	scale = Vector2(0, 0)
	modulate.a = 0.0
	
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), 0.3)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.3)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	# 启动辉光粒子
	if glow_particles and not low_effects:
		glow_particles.emitting = true
		glow_particles.restart()

## 更新图标视觉（道具）
func _update_icon_visual() -> void:
	# 隐藏形状，显示图标
	if polygon:
		polygon.visible = false
	if sprite and item_data:
		sprite.visible = true
		sprite.texture = item_data.icon
		sprite.modulate = _get_rarity_color()
		
		# 更新辉光粒子颜色
		if glow_particles:
			update_particle_color(_get_rarity_color())

## 获取稀有度颜色（用于道具）
## [return: Color] 根据稀有度返回颜色
func _get_rarity_color() -> Color:
	if not item_data:
		return Color.WHITE
	
	match item_data.rarity:
		"COMMON":
			return Color.WHITE
		"RARE":
			return Color.CYAN
		"EPIC":
			return Color.MAGENTA
		_:
			return Color.WHITE

## 移动完成回调
func _on_move_completed() -> void:
	_is_moving = false
	movement_completed.emit()
