class_name SkillRarity
extends RefCounted

const LABELS: Array[String] = ["白·普通", "绿·优秀", "蓝·稀有", "紫·史诗", "橙·传说"]
const NAMES: Array[String] = ["普通", "优秀", "稀有", "史诗", "传说"]
const COLORS: Array[Color] = [Color("cbd5e1"), Color("67d98b"), Color("62aaff"), Color("bb83ed"), Color("ffae57")]

static func color_for(rarity: SkillDefinition.Rarity, preset: GameTheme = null) -> Color:
	return preset.ui_theme.get_color("rarity_%d" % rarity, "Game") if preset != null else COLORS[rarity]

static func style(button: Button, rarity: SkillDefinition.Rarity, preset: GameTheme = null) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color("131e2e") if state in ["normal", "disabled"] else Color("203249")
		box.border_color = Color(COLORS[rarity], 0.65 if state == "normal" else 1.0)
		if state == "disabled": box.border_color = Color("37465a")
		box.set_border_width_all(2)
		box.set_corner_radius_all(12)
		if state in ["hover", "focus"]:
			box.shadow_color = Color(COLORS[rarity], 0.16)
			box.shadow_size = 9
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 14.0
		box.content_margin_bottom = 14.0
		if preset != null:
			box.bg_color = preset.ui_theme.get_color("surface" if state in ["normal", "disabled"] else "hover", "Game")
			box.border_color = color_for(rarity, preset)
			box.set_corner_radius_all(preset.ui_theme.get_constant("rounding", "Game"))
			box.set_border_width_all(0)
			box.border_width_top = 3
			if state in ["hover", "focus", "pressed"]: box.set_border_width_all(2)
			box.shadow_size = 0
		button.add_theme_stylebox_override(state, box)
