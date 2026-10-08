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
var _target: SkillTarget
var _error: String = ""

func _ready() -> void:
	for index: int in range(colors.get_child_count()):
		var button: Button = colors.get_child(index) as Button
		button.pressed.connect(select_color.bind(index))
	confirm_button.pressed.connect(confirm_selection)
	back_button.pressed.connect(back_requested.emit)

func configure(target: SkillTarget) -> void:
	_target = target
	_error = ""
	selected_color = -1
	_render_colors()
	frame.add_theme_stylebox_override("panel", normal_frame)
	hint.text = tr("请选择要清理的颜色；确认前可以查看棋盘或返回三选一。")
	hint.remove_theme_color_override("font_color")

func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready() or _target == null: return
	_render_colors()
	if selected_color >= 0: _show_selected_hint()
	elif _error.is_empty(): hint.text = tr("请选择要清理的颜色；确认前可以查看棋盘或返回三选一。")
	if not _error.is_empty(): hint.text = tr(_error)

func _render_colors() -> void:
	var target: SkillTarget = _target
	for color: int in range(colors.get_child_count()):
		var button: Button = colors.get_child(color) as Button
		var count: int = target.color_groups[color].size() if color < target.color_groups.size() else 0
		var fuses: int = target.fuse_counts[color] if color < target.fuse_counts.size() else 0
		button.text = tr("%s · %s\n\n直接清理 %d 枚\n其中引信 %d 枚") % [tr(PieceTooltip.COLOR_NAMES[color]), [tr("圆形"), tr("方形"), tr("三角形"), tr("五边形"), tr("星形")][color], count, fuses]
		button.disabled = count == 0
		button.set_pressed_no_signal(color == selected_color)
		if color == selected_color: button.text = tr("✓ 已选\n") + button.text

func select_color(color: int) -> void:
	if color < 0 or color >= colors.get_child_count(): return
	var selected: Button = colors.get_child(color) as Button
	if selected.disabled: return
	selected_color = color
	_error = ""
	_render_colors()
	frame.add_theme_stylebox_override("panel", normal_frame)
	_show_selected_hint()
	hint.remove_theme_color_override("font_color")

func _show_selected_hint() -> void:
	hint.text = tr("已选择%s。点击“确认清理”后才会应用技能。") % tr(PieceTooltip.COLOR_NAMES[selected_color])

func confirm_selection() -> void:
	if selected_color == -1:
		show_error("请先选择颜色", false)
		return
	confirmed.emit(selected_color)

func show_error(reason: String, reset_selection: bool = true) -> void:
	_error = reason
	if reset_selection:
		selected_color = -1
		_render_colors()
	frame.add_theme_stylebox_override("panel", error_frame)
	hint.text = tr(reason)
	hint.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	for button: Button in colors.get_children():
		if not button.disabled:
			button.grab_focus()
			break
