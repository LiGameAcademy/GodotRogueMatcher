extends Control

## 道具提示框
## 鼠标悬停时显示道具信息

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var type_label: Label = $Panel/VBox/TypeLabel
@onready var desc_label: Label = $Panel/VBox/DescLabel

func _ready() -> void:
	hide()

## 显示道具提示
## [param item_data: ItemData] 道具数据
## [param screen_pos: Vector2] 屏幕位置
func show_tooltip(item_data: ItemData, screen_pos: Vector2) -> void:
	if not item_data:
		hide()
		return

	# 设置文本
	name_label.text = item_data.get_localized_name()
	type_label.text = "[%s] %s" % [item_data.rarity, item_data.get_localized_type()]

	var desc = item_data.get_localized_description()
	desc_label.text = desc if not desc.is_empty() else item_data.get_effect_description()

	# 显示
	visible = true

	# 设置位置（确保不超出屏幕）
	position = screen_pos
	var panel_size = panel.size
	if position.x + panel_size.x > get_viewport_rect().size.x:
		position.x = screen_pos.x - panel_size.x
	if position.y + panel_size.y > get_viewport_rect().size.y:
		position.y = screen_pos.y - panel_size.y

	# 播放淡入动画
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

## 隐藏提示
func hide_tooltip() -> void:
	visible = false
	modulate.a = 0.0