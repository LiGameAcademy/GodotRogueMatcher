class_name ColorTargetPicker
extends VBoxContainer

signal confirmed(color: int)
signal back_requested

@export var normal_frame: StyleBoxFlat
@export var error_frame: StyleBoxFlat
@onready var frame: PanelContainer = $Frame
@onready var colors: HBoxContainer = $Frame/Margin/Colors
@onready var hint: Label = $Hint
@onready var confirm_button: Button = $Actions/Confirm
@onready var back_button: Button = $Actions/Back
var selected_color: int = -1

func _ready() -> void:
	for index: int in range(colors.get_child_count()):
		var button: Button = colors.get_child(index) as Button
		button.pressed.connect(select_color.bind(index))
	confirm_button.pressed.connect(confirm_selection)
	back_button.pressed.connect(back_requested.emit)

func configure(target: SkillTarget) -> void:
	selected_color = -1
	for color: int in range(colors.get_child_count()):
		var button: Button = colors.get_child(color) as Button
		var count: int = target.color_groups[color].size() if color < target.color_groups.size() else 0
		var fuses: int = target.fuse_counts[color] if color < target.fuse_counts.size() else 0
		button.text = "%s · %s\n\n直接清理 %d 枚\n其中引信 %d 枚" % [PieceTooltip.COLOR_NAMES[color], ["圆形", "方形", "三角形", "五边形", "星形"][color], count, fuses]
		button.disabled = count == 0
		button.set_pressed_no_signal(false)
	frame.add_theme_stylebox_override("panel", normal_frame)
	hint.text = "请选择要清理的颜色；确认前可以查看棋盘或返回三选一。"
	hint.remove_theme_color_override("font_color")

func select_color(color: int) -> void:
	if color < 0 or color >= colors.get_child_count(): return
	var selected: Button = colors.get_child(color) as Button
	if selected.disabled: return
	selected_color = color
	for index: int in range(colors.get_child_count()):
		var button: Button = colors.get_child(index) as Button
		button.set_pressed_no_signal(index == color)
		button.text = ("✓ 已选\n" if index == color else "") + button.text.trim_prefix("✓ 已选\n")
	frame.add_theme_stylebox_override("panel", normal_frame)
	hint.text = "已选择%s。点击“确认清理”后才会应用技能。" % PieceTooltip.COLOR_NAMES[color]
	hint.remove_theme_color_override("font_color")

func confirm_selection() -> void:
	if selected_color == -1:
		show_error("请先选择颜色", false)
		return
	confirmed.emit(selected_color)

func show_error(reason: String, reset_selection: bool = true) -> void:
	if reset_selection:
		selected_color = -1
		for button: Button in colors.get_children():
			button.set_pressed_no_signal(false)
			button.text = button.text.trim_prefix("✓ 已选\n")
	frame.add_theme_stylebox_override("panel", error_frame)
	hint.text = reason
	hint.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	for button: Button in colors.get_children():
		if not button.disabled:
			button.grab_focus()
			break
