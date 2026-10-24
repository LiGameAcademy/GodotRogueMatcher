class_name GameThemeUi
extends RefCounted

const BUILD_CARD: Script = preload("res://ui/build_card/build_card.gd")

## Apply through explicit UI roots, including modals on separate CanvasLayers.
## Clear scene skin overrides, retaining geometry/font sizes and runtime selection state.
static func apply(root: Node, preset: GameTheme) -> void:
	if root is Control:
		var control: Control = root as Control
		control.theme = preset.ui_theme
		for name_text: StringName in [&"font_color", &"default_color"]:
			control.remove_theme_color_override(name_text)
		if control is PanelContainer: control.remove_theme_stylebox_override("panel")
		if control is Button and not control is SkillCard:
			for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]: control.remove_theme_stylebox_override(state)
		if control is Label or control is RichTextLabel:
			var role: StringName = &"muted" if control.name in [&"Hint", &"Version", &"Notice", &"Kind", &"Metadata", &"Level", &"Action", &"Empty", &"Message", &"Flavor"] else &"text"
			control.add_theme_color_override("default_color" if control is RichTextLabel else "font_color", preset.ui_theme.get_color(role, "Game"))
		if control is ColorRect and control.name in [&"Backdrop", &"Shade", &"BackgroundOverlay"]:
			(control as ColorRect).color = Color(preset.background, 0.96)
	for child: Node in root.get_children(): apply(child, preset)
	if root is SkillCard: (root as SkillCard).apply_game_theme(preset)
	elif root is BUILD_CARD: (root as BUILD_CARD).apply_game_theme(preset)
	elif root is SpawnPreview: (root as SpawnPreview).apply_game_theme(preset)
	elif root is BoardView: (root as BoardView).apply_game_theme(preset)
	elif root is ColorTargetPicker: (root as ColorTargetPicker).apply_game_theme(preset)
