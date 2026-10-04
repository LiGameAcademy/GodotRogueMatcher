extends Control
class_name PopupLevelUp

## 升级弹窗
## 显示三选一道具界面

## 节点引用
@onready var title_label: Label = $Container/TitleLabel # 标题标签
@onready var options_container: HBoxContainer = $Container/OptionsContainer # 选项容器
@onready var background_overlay: ColorRect = $BackgroundOverlay # 背景覆盖
@onready var container: VBoxContainer = $Container # 容器

## 道具选项
var item_options: Array[ItemData] = []

## 动画状态
var tween: Tween = null
## 是否正在动画
var is_animating: bool = false

## 信号：道具被选中
signal item_selected(item_data: ItemData)
signal closed

## 初始化
func _ready() -> void:
	# 初始化状态
	visible = false
	modulate.a = 0.0
	container.scale = Vector2(0.8, 0.8)
	
	# 连接道具选择信号
	for i: int in range(options_container.get_child_count()):
		var widget: ItemWidget = options_container.get_child(i) as ItemWidget
		if widget:
			widget.item_selected.connect(_on_item_selected)

## 初始化弹窗（统一接口，符合开闭原则）
## [param data: Dictionary] 初始化数据，应包含 "items" 键
func initialize(data: Dictionary = {}) -> void:
	if "items" in data:
		show_options(data.items)
	else:
		push_warning("PopupLevelUp 需要 'items' 数据")

## 显示弹窗
## [param items: Array[ItemData]] 三个道具选项
func show_options(items: Array[ItemData]) -> void:
	if items.size() < 3:
		print("错误：需要至少 3 个道具选项")
		return
	
	item_options = items
	
	# 设置标题
	if title_label:
		title_label.text = tr("message.level_up")
	
	# 更新道具控件
	update_item_widgets()
	
	# 显示并播放动画
	visible = true
	play_show_animation()
	
	# 暂停游戏
	get_tree().paused = true

## 更新道具控件
func update_item_widgets() -> void:
	for i: int in range(min(item_options.size(), options_container.get_child_count())):
		var widget: ItemWidget = options_container.get_child(i) as ItemWidget
		var item_data: ItemData = item_options[i]
		
		if widget and item_data:
			widget.item_data = item_data
			# 播放出现动画（带延迟）
			widget.play_spawn_animation(i * 0.1)

## 播放显示动画
func play_show_animation() -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	# 背景淡入
	tween.tween_property(background_overlay, "modulate:a", 0.8, 0.3)
	
	# 容器淡入并放大
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(container, "scale", Vector2(1.0, 1.0), 0.4)

## 播放隐藏动画
func play_hide_animation() -> void:
	if tween:
		tween.kill()
	
	is_animating = true
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	
	# 背景淡出
	tween.tween_property(background_overlay, "modulate:a", 0.0, 0.2)
	
	# 容器淡出并缩小
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(container, "scale", Vector2(0.8, 0.8), 0.2)
	
	# 道具控件消失动画
	for widget: Node in options_container.get_children():
		if widget is ItemWidget:
			widget.play_dismiss_animation()
	
	await tween.finished
	is_animating = false

## 播放选择反馈
func play_selection_feedback(selected_item: ItemData) -> void:
	var feedback_tween: Tween = create_tween()
	feedback_tween.set_parallel(true)
	# 高亮选中的道具，淡化其他道具
	for widget: Node in options_container.get_children():
		if widget is ItemWidget:
			if widget.item_data == selected_item:
				# 选中的道具：继续高亮
				pass
			else:
				# 其他道具：淡化
				feedback_tween.tween_property(widget, "modulate:a", 0.3, 0.3)

## 关闭弹窗
func close_popup() -> void:
	await play_hide_animation()
	
	# 恢复游戏
	get_tree().paused = false
	
	# 关闭弹窗
	hide()
	closed.emit()
	queue_free()

## 道具选择回调
func _on_item_selected(item_data: ItemData) -> void:
	if is_animating:
		return
	is_animating = true
	
	# 播放选择反馈
	play_selection_feedback(item_data)
	
	# 发出信号
	item_selected.emit(item_data)
	
	# 延迟后关闭（让玩家看到选择效果）
	await get_tree().create_timer(0.5).timeout
	close_popup()
