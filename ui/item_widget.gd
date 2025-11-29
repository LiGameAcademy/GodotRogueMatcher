extends Control
class_name ItemWidget

## 道具控件
## 用于显示单个道具选项，包含图标、名称、描述和稀有度标识

## 稀有度颜色配置
const RARITY_COLORS: Dictionary = {
	"COMMON": Color(1.0, 1.0, 1.0, 0.3),      ## 白色，半透明
	"RARE": Color(0.0, 1.0, 1.0, 0.5),        ## 青色
	"EPIC": Color(1.0, 0.0, 1.0, 0.6)         ## 紫色
}

# 节点引用
@onready var icon_sprite: Sprite2D = $Card/IconSprite # 图标精灵
@onready var name_label: Label = $Card/NameLabel # 名称标签
@onready var description_label: Label = $Card/DescriptionLabel # 描述标签
@onready var rarity_border: Panel = $Card/RarityBorder # 稀有度边框
@onready var card_panel: Panel = $Card # 卡片面板
@onready var hover_glow: ColorRect = $Card/HoverGlow # 悬停光晕

## 道具数据
var item_data: ItemData = null:
	set(value):
		item_data = value
		update_display()

# 状态
# 是否悬停
var is_hovered: bool = false
# 是否选中
var is_selected: bool = false
# 动画
var tween: Tween = null

## 信号：道具被选中
signal item_selected(item_data: ItemData)

func _ready() -> void:
	# 连接鼠标事件（PC端）
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# 连接输入事件（支持鼠标和触摸）
	gui_input.connect(_on_gui_input)
	
	# 初始化状态
	if hover_glow:
		hover_glow.visible = false
	update_display()

## 更新显示内容
func update_display() -> void:
	if not is_inside_tree():
		await ready
	
	if not item_data:
		return
	
	# 设置图标
	if icon_sprite and item_data.icon:
		icon_sprite.texture = item_data.icon
	
	# 设置名称
	if name_label:
		name_label.text = item_data.get_localized_name()
	
	# 设置描述
	if description_label:
		description_label.text = item_data.get_localized_description()
	
	# 设置稀有度边框颜色
	if rarity_border:
		var rarity_color = RARITY_COLORS.get(item_data.rarity, RARITY_COLORS["COMMON"])
		rarity_border.modulate = rarity_color

## 选择道具
func select_item() -> void:
	if is_selected or not item_data:
		return
	
	is_selected = true
	play_select_animation()
	item_selected.emit(item_data)

## 播放悬停动画
func play_hover_animation() -> void:
	if tween:
		tween.kill()
	
	hover_glow.visible = true
	tween = create_tween()
	tween.set_parallel(true)
	
	# 卡片放大
	tween.tween_property(card_panel, "scale", Vector2(1.05, 1.05), 0.2)
	tween.tween_property(card_panel, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.2)
	
	# 悬停光晕淡入
	tween.tween_property(hover_glow, "modulate:a", 0.6, 0.2)

## 播放取消悬停动画
func play_unhover_animation() -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	
	# 卡片恢复
	tween.tween_property(card_panel, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_property(card_panel, "modulate", Color.WHITE, 0.2)
	
	# 悬停光晕淡出
	tween.tween_property(hover_glow, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): hover_glow.visible = false)

## 播放选择动画
func play_select_animation() -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	
	# 选中效果：放大并高亮
	tween.tween_property(card_panel, "scale", Vector2(1.15, 1.15), 0.15)
	tween.tween_property(card_panel, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.15)
	
	# 稀有度边框高亮
	if rarity_border:
		var rarity_color = RARITY_COLORS.get(item_data.rarity, RARITY_COLORS["COMMON"])
		rarity_color.a = 1.0
		tween.tween_property(rarity_border, "modulate", rarity_color, 0.15)
	
	# 悬停光晕增强
	hover_glow.visible = true
	tween.tween_property(hover_glow, "modulate:a", 1.0, 0.15)

## 播放出现动画
func play_spawn_animation(delay: float = 0.0) -> void:
	# 初始状态：透明且缩小
	modulate.a = 0.0
	card_panel.scale = Vector2(0.5, 0.5)
	card_panel.position.y = -20
	
	# 等待延迟
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	# 淡入
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	
	# 放大并弹起
	tween.tween_property(card_panel, "scale", Vector2(1.0, 1.0), 0.4)
	tween.tween_property(card_panel, "position:y", 0.0, 0.4)

## 播放消失动画
func play_dismiss_animation() -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	
	# 淡出
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	
	# 缩小
	tween.tween_property(card_panel, "scale", Vector2(0.5, 0.5), 0.3)
	
	await tween.finished

## 重置状态
func reset_state() -> void:
	is_selected = false
	is_hovered = false
	card_panel.scale = Vector2(1.0, 1.0)
	card_panel.modulate = Color.WHITE
	card_panel.position.y = 0.0
	modulate.a = 1.0
	hover_glow.visible = false
	hover_glow.modulate.a = 0.0

## 鼠标进入
func _on_mouse_entered() -> void:
	if is_selected:
		return
	
	is_hovered = true
	play_hover_animation()

## 鼠标离开
func _on_mouse_exited() -> void:
	if is_selected:
		return
	
	is_hovered = false
	play_unhover_animation()

## 输入事件
## 支持鼠标和触摸输入（移动端兼容）
func _on_gui_input(event: InputEvent) -> void:
	# 鼠标点击（PC端）
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_item()
			get_viewport().set_input_as_handled()
	# 触摸输入（移动端支持）
	elif event is InputEventScreenTouch:
		if event.pressed:
			# 触摸反馈：播放触摸动画
			# play_touch_feedback()
			select_item()
			get_viewport().set_input_as_handled()
