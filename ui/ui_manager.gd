extends CanvasLayer
## 简化的 UI 管理器
## 职责：提供便捷的 UI 打开/关闭方法

## UI 场景路径
const UI_PATH: String = "res://ui/"

## 当前打开的弹窗
var current_popup: Control = null

func _ready() -> void:
	layer = 129
	process_mode = Node.PROCESS_MODE_ALWAYS

## 打开弹窗
## [param popup_name: String] 弹窗名称（不含 .tscn 扩展名）
## [param data: Dictionary] 传递给弹窗的数据
## [return: Control] 打开的弹窗实例
func open_popup(popup_name: String, data: Dictionary = {}) -> Control:
	# 如果已有弹窗，先关闭
	if is_instance_valid(current_popup):
		close_popup()
	
	# 加载并实例化弹窗
	var popup_path: String = UI_PATH + popup_name + ".tscn"
	if not ResourceLoader.exists(popup_path):
		push_error("弹窗资源不存在: " + popup_path)
		return null
	
	var popup_scene: PackedScene = load(popup_path) as PackedScene
	var popup: Control = popup_scene.instantiate() as Control
	
	# 添加到场景树
	add_child(popup)
	current_popup = popup
	popup.tree_exiting.connect(_on_popup_exiting.bind(popup), CONNECT_ONE_SHOT)
	
	# 等待一帧，确保节点已完全初始化
	await get_tree().process_frame
	# 重试/关闭可能发生在这一帧内；旧弹窗不得初始化或暂停新局。
	if not is_instance_valid(popup) or popup.is_queued_for_deletion() or current_popup != popup:
		return null
	
	# 调用统一的初始化方法（如果弹窗实现了该方法）
	if popup.has_method("initialize"):
		popup.initialize(data)
	
	popup.show()
	return popup

## 关闭当前弹窗
func close_popup() -> void:
	if is_instance_valid(current_popup):
		if current_popup is PopupSkillChoice:
			(current_popup as PopupSkillChoice).accept_selection()
		else:
			current_popup.queue_free()
	current_popup = null

func _on_popup_exiting(popup: Control) -> void:
	if current_popup == popup: current_popup = null
