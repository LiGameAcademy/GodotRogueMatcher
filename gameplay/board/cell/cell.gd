extends Node2D
class_name Cell

## 节点引用
@onready var background: ColorRect = %Background
@onready var border: Line2D = %Border
@onready var glow_border: Line2D = %GlowBorder
@onready var scan_line: ColorRect = %ScanLine
@onready var area_2d: Area2D = %Area2D

## 颜色配置（赛博风格）
@export var default_bg_color: Color = Color.html("#0a0a0a")  # 深黑色背景
@export var default_border_color: Color = Color.html("#2a2a2a")  # 深灰色边框
@export var highlight_bg_color: Color = Color.html("#001a1a")  # 深青色背景
@export var highlight_glow_color: Color = Color.html("#00ffff")  # 霓虹青色发光
@export var path_highlight_color: Color = Color.html("#0080ff")  # 霓虹蓝色
@export var hover_color: Color = Color.html("#1a1a2a")  # 悬停时背景

## 仅查询显示子节点，不存储规则占格。
var piece: ChessPiece:
	get:
		return get_node_or_null("Piece") as ChessPiece

signal pressed(cell: Cell)

## 状态
var is_path_highlighted: bool = false
var is_hovered: bool = false
var highlight_tween: Tween = null
var scan_tween: Tween = null
var path_tween: Tween = null

## 网格坐标（在棋盘当中的坐标）
var coordinate: Vector2i = Vector2i.ZERO
var low_effects: bool = false

func set_low_effects(enabled: bool) -> void:
	low_effects = enabled
	stop_scan_animation()
	if path_tween != null: path_tween.kill()
	if highlight_tween != null: highlight_tween.kill()
	glow_border.default_color = Color.TRANSPARENT
	background.modulate = Color.WHITE
	if is_path_highlighted:
		is_path_highlighted = false
		highlight_path()
	else:
		update_default_style()
		if is_hovered: hover_effect(true)
		else: start_scan_animation()

func _ready() -> void:
	area_2d.input_event.connect(_on_area_2d_input_event)
	area_2d.mouse_entered.connect(_on_mouse_entered)
	area_2d.mouse_exited.connect(_on_mouse_exited)
	
	# 初始化视觉状态
	update_default_style()
	
	# 启动扫描线动画（可选，低频率）
	start_scan_animation()

## 以下方法仅供BoardView管理显示，不提交游戏规则。
func show_piece(display_piece: ChessPiece) -> void:
	display_piece.name = "Piece"
	add_child(display_piece)

func take_piece() -> ChessPiece:
	var display_piece: ChessPiece = piece
	if is_instance_valid(display_piece):
		remove_child(display_piece)
	return display_piece

## 更新默认样式
func update_default_style() -> void:
	if background:
		background.color = default_bg_color
	if border:
		border.default_color = default_border_color
	if glow_border:
		glow_border.default_color = Color(0, 0, 0, 0)  # 默认透明
	if scan_line:
		scan_line.color = Color(0, 0, 0, 0)  # 默认透明

## 鼠标进入
func _on_mouse_entered() -> void:
	if is_path_highlighted or piece != null:
		return
	
	is_hovered = true
	hover_effect(true)

## 鼠标离开
func _on_mouse_exited() -> void:
	if is_path_highlighted:
		return
	
	is_hovered = false
	hover_effect(false)

## 悬停效果
func hover_effect(enter: bool) -> void:
	if highlight_tween:
		highlight_tween.kill()
	
	highlight_tween = create_tween()
	highlight_tween.set_trans(Tween.TRANS_QUART)
	highlight_tween.set_ease(Tween.EASE_OUT)
	
	if enter:
		highlight_tween.tween_property(background, "color", hover_color, 0.15)
		highlight_tween.parallel().tween_property(border, "default_color", Color(0.4, 0.4, 0.4, 1.0), 0.15)
	else:
		highlight_tween.tween_property(background, "color", default_bg_color, 0.15)
		highlight_tween.parallel().tween_property(border, "default_color", default_border_color, 0.15)

func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			# 点击反馈
			click_feedback()
			pressed.emit(self)

## 点击反馈
func click_feedback() -> void:
	if low_effects: return
	# 快速闪烁效果
	var flash_tween: Tween = create_tween()
	flash_tween.set_trans(Tween.TRANS_QUART)
	flash_tween.tween_property(background, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.05)
	flash_tween.tween_property(background, "modulate", Color.WHITE, 0.1)

## 高亮（选中时）
func highlight() -> void:
	if highlight_tween:
		highlight_tween.kill()
	
	highlight_tween = create_tween()
	highlight_tween.set_trans(Tween.TRANS_QUART)
	highlight_tween.set_ease(Tween.EASE_OUT)
	
	# 背景颜色变化
	highlight_tween.tween_property(background, "color", highlight_bg_color, 0.2)
	
	# 边框发光效果
	highlight_tween.parallel().tween_property(border, "default_color", highlight_glow_color, 0.2)
	highlight_tween.parallel().tween_property(glow_border, "default_color", Color(highlight_glow_color.r, highlight_glow_color.g, highlight_glow_color.b, 0.6), 0.2)
	if low_effects: glow_border.visible = false
	
	# 启动扫描线动画
	start_scan_animation(highlight_glow_color, 0.8)

## 路径高亮（移动路径）
func highlight_path() -> void:
	if is_path_highlighted:
		return
	
	is_path_highlighted = true
	if highlight_tween:
		highlight_tween.kill()
	
	highlight_tween = create_tween()
	highlight_tween.set_trans(Tween.TRANS_QUART)
	highlight_tween.set_ease(Tween.EASE_OUT)
	
	# 背景颜色变化
	highlight_tween.tween_property(background, "color", Color(path_highlight_color.r * 0.1, path_highlight_color.g * 0.1, path_highlight_color.b * 0.1, 1.0), 0.15)
	
	# 边框颜色变化
	highlight_tween.parallel().tween_property(border, "default_color", path_highlight_color, 0.15)
	highlight_tween.parallel().tween_property(glow_border, "default_color", Color(path_highlight_color.r, path_highlight_color.g, path_highlight_color.b, 0.4), 0.15)
	glow_border.visible = not low_effects
	if low_effects: return
	
	# 脉冲效果
	path_tween = create_tween()
	path_tween.set_loops()
	path_tween.tween_property(glow_border, "default_color", Color(path_highlight_color.r, path_highlight_color.g, path_highlight_color.b, 0.2), 0.5)
	path_tween.tween_property(glow_border, "default_color", Color(path_highlight_color.r, path_highlight_color.g, path_highlight_color.b, 0.6), 0.5)
	
	# 启动扫描线动画
	start_scan_animation(path_highlight_color, 0.6)

## 取消高亮
func unhighlight() -> void:
	is_path_highlighted = false
	if path_tween != null:
		path_tween.kill()
		path_tween = null
	if highlight_tween:
		highlight_tween.kill()
	
	highlight_tween = create_tween()
	highlight_tween.set_trans(Tween.TRANS_QUART)
	highlight_tween.set_ease(Tween.EASE_OUT)
	
	# 恢复默认样式
	highlight_tween.tween_property(background, "color", default_bg_color, 0.2)
	highlight_tween.parallel().tween_property(border, "default_color", default_border_color, 0.2)
	highlight_tween.parallel().tween_property(glow_border, "default_color", Color(0, 0, 0, 0), 0.2)
	highlight_tween.parallel().tween_property(background, "modulate", Color.WHITE, 0.2)
	
	# 停止扫描线
	stop_scan_animation()

## 启动扫描线动画（CRT 终端风格）
func start_scan_animation(color: Color = Color(0, 1, 1, 0.3), intensity: float = 0.3) -> void:
	if low_effects:
		glow_border.visible = false
		return
	glow_border.visible = true
	if not scan_line:
		return
	
	if scan_tween:
		scan_tween.kill()
	
	# 设置扫描线颜色
	scan_line.color = Color(color.r, color.g, color.b, 0)
	
	# 扫描线从上到下移动
	scan_tween = create_tween()
	scan_tween.set_loops()
	
	# 移动到顶部并显示
	scan_line.position.y = -32
	scan_tween.tween_property(scan_line, "position:y", -32, 0.0)
	scan_tween.tween_property(scan_line, "color", Color(color.r, color.g, color.b, intensity), 0.1)
	
	# 向下扫描
	scan_tween.tween_property(scan_line, "position:y", 32, 0.8)
	
	# 淡出
	scan_tween.tween_property(scan_line, "color", Color(color.r, color.g, color.b, 0), 0.1)
	
	# 等待下一次扫描（随机延迟，模拟 CRT 效果）
	scan_tween.tween_interval(randf_range(1.0, 3.0))

## 停止扫描线动画
func stop_scan_animation() -> void:
	if scan_tween:
		scan_tween.kill()
		scan_tween = null
	
	if scan_line:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(scan_line, "color", Color(0, 0, 0, 0), 0.2)

func _to_string() -> String:
	return name + ":" + str(self.coordinate)
