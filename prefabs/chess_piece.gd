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

## 节点引用
@onready var polygon: Polygon2D = $Polygon2D
@onready var glow_particles: GPUParticles2D = $GlowParticles

## 棋子类型（0-4，对应5种颜色）
var piece_type: int = 0 :
	set(value):
		piece_type = value
		update_visual()

var tween: Tween = null
var is_selected: bool = false
var is_eliminating: bool = false

func _ready() -> void:
	update_visual()
	setup_glow_particles()

## 更新视觉效果
## 色盲友好：颜色和形状严格一一对应
func update_visual() -> void:
	if not is_inside_tree():
		await ready
	
	if polygon:
		# 确保 piece_type 在有效范围内
		var type_index = piece_type % PIECE_COLORS.size()
		var color = PIECE_COLORS[type_index]
		var shape_type = type_index as ShapeType  # 颜色和形状一一对应
		
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
	var points = PackedVector2Array()
	for i in range(segments):
		var angle = (i * TAU) / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

## 生成方形多边形
func generate_square_polygon(size: float) -> PackedVector2Array:
	var half = size * 0.707  # 对角线的一半
	return PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half)
	])

## 生成三角形多边形
func generate_triangle_polygon(size: float) -> PackedVector2Array:
	var height = size * 0.866  # 等边三角形高度
	return PackedVector2Array([
		Vector2(0, -size),
		Vector2(height, size * 0.5),
		Vector2(-height, size * 0.5)
	])

## 生成五边形多边形（色盲友好：黄色）
func generate_pentagon_polygon(size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(5):
		var angle = (i * TAU / 5) - (TAU / 4)  # 从顶部开始，旋转90度
		points.append(Vector2(cos(angle), sin(angle)) * size)
	return points

## 生成星形多边形（色盲友好：紫色）
func generate_star_polygon(size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var outer_radius = size
	var inner_radius = size * 0.4  # 内圆半径
	for i in range(10):  # 5个外点 + 5个内点
		var angle = (i * TAU / 10) - (TAU / 4)  # 从顶部开始
		var radius = outer_radius if i % 2 == 0 else inner_radius
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
	
	# 设置粒子材质
	var particle_material = ParticleProcessMaterial.new()
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
	
	var particle_material = glow_particles.process_material as ParticleProcessMaterial
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
	tween.set_loops()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
	
	# 启动辉光粒子
	if glow_particles:
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

## 移动动画效果
func move_to(target_cell: Cell) -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", target_cell.position, 0.15)
	await tween.finished

## 消除动画
func eliminate() -> void:
	if is_eliminating:
		return
	
	is_eliminating = true
	
	# 爆炸粒子效果
	if glow_particles:
		glow_particles.emitting = true
		glow_particles.restart()
		var particle_material = glow_particles.process_material as ParticleProcessMaterial
		if particle_material:
			particle_material.initial_velocity_min = 20.0
			particle_material.initial_velocity_max = 50.0
	
	# 缩放和旋转动画
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.parallel().tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	tween.parallel().tween_property(self, "rotation", rotation + TAU, 0.2)
	tween.parallel().tween_property(polygon, "modulate:a", 0.0, 0.2)
	await tween.finished
	
	# 清理
	queue_free()

## 重置状态
func reset() -> void:
	is_selected = false
	is_eliminating = false
	scale = Vector2.ONE
	rotation = 0.0
	if polygon:
		polygon.modulate.a = 1.0
	if glow_particles:
		glow_particles.emitting = false
