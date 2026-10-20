extends RichTextLabel
## 卡面术语提示，不显示整卡规则。

const DETAILS: PackedScene = preload("res://ui/skill_details.tscn")
const DETAILS_SCRIPT: Script = preload("res://ui/skill_details.gd")

func _make_custom_tooltip(for_text: String) -> Object:
	var details: DETAILS_SCRIPT = DETAILS.instantiate() as DETAILS_SCRIPT
	details.configure(for_text, minf(380.0, get_viewport_rect().size.x - 32.0))
	return details
