extends CanvasLayer
## 简化的 UI 管理器
## 职责：提供便捷的 UI 打开/关闭方法

## UI 场景路径
const UI_PATH: String = "res://ui/"

## 当前打开的弹窗
var current_popup: Control = null

func _ready() -> void:
	layer = 129

## 打开弹窗
## [param popup_name: String] 弹窗名称（不含 .tscn 扩展名）
## [param data: Dictionary] 传递给弹窗的数据
## [return: Control] 打开的弹窗实例
func open_popup(popup_name: String, data: Dictionary = {}) -> Control:
	# 如果已有弹窗，先关闭
	if current_popup:
		close_popup()
	
	# 加载并实例化弹窗
	var popup_path = UI_PATH + popup_name + ".tscn"
	if not ResourceLoader.exists(popup_path):
		push_error("弹窗资源不存在: " + popup_path)
		return null
	
	var popup_scene = load(popup_path) as PackedScene
	var popup = popup_scene.instantiate() as Control
	
	# 添加到场景树
	add_child(popup)
	current_popup = popup
	
	# 根据弹窗类型调用相应方法
	if popup is PopupLevelUp and "items" in data:
		popup.show_options(data.items)
	
	popup.show()
	return popup

## 关闭当前弹窗
func close_popup() -> void:
	if current_popup:
		current_popup.queue_free()
		current_popup = null
