extends PanelContainer

## 只读术语提示；宽度受窗口约束，不重新生成候选。
@export var rules_label: Label

## 在加入原生提示窗口前完成测量，避免0宽度造成逐字折行。
func configure(text: String, wrap_width: float) -> void:
	custom_minimum_size.x = wrap_width
	rules_label.custom_minimum_size.x = maxf(1.0, wrap_width - 32.0)
	rules_label.size.x = rules_label.custom_minimum_size.x
	rules_label.text = text
	size = get_combined_minimum_size()
