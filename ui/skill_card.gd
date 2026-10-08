class_name SkillCard
extends Button

## 独立卡面只消费定义和冻结目标，选择仍由弹窗提交命令。
@onready var rarity_label: Label = %Rarity
@onready var kind_label: Label = %Kind
@onready var title_label: Label = %Title
@onready var level_label: Label = %Level
@onready var effect_label: Label = %Effect
@onready var preview_label: Label = %Preview
@onready var action_label: Label = %Action
@onready var emblem_label: Label = %Emblem
@onready var rarity_frame: PanelContainer = %RarityFrame
@onready var emblem_frame: PanelContainer = %EmblemFrame
@onready var preview_frame: PanelContainer = %PreviewFrame
@onready var action_frame: PanelContainer = %ActionFrame
@onready var content: MarginContainer = $Content
@export var hover_duration: float = 0.12
var _motion: Tween
var _accent: Color = Color.WHITE
var _skill: SkillDefinition
var _target: SkillTarget

func _ready() -> void:
	_ignore_child_mouse(content)
	mouse_entered.connect(_update_feedback)
	mouse_exited.connect(_update_feedback)
	focus_entered.connect(_update_feedback)
	focus_exited.connect(_update_feedback)
	button_down.connect(_press_feedback)
	button_up.connect(_update_feedback)

func _exit_tree() -> void:
	if _motion != null: _motion.kill()

func configure(skill: SkillDefinition, target: SkillTarget) -> void:
	_skill = skill
	_target = target
	_accent = SkillRarity.COLORS[skill.rarity]
	SkillRarity.style(self, skill.rarity)
	rarity_label.text = tr(SkillRarity.LABELS[skill.rarity])
	rarity_label.add_theme_color_override("font_color", _accent)
	kind_label.text = SkillChoiceText.kind(skill)
	title_label.text = tr(skill.title)
	level_label.text = SkillChoiceText.level_text(skill, target)
	effect_label.text = tr(skill.description)
	preview_label.text = SkillChoiceText.preview(skill, target)
	preview_frame.visible = not preview_label.text.is_empty()
	action_label.text = tr("选择颜色 →") if skill.choice_effect != null and skill.choice_effect.requires_color_choice() else tr("选择此技能 →")
	emblem_label.text = SkillChoiceText.emblem(skill)
	emblem_label.add_theme_color_override("font_color", _accent)
	_style_frame(rarity_frame, 0.1)
	_style_frame(emblem_frame, 0.12)
	_style_frame(action_frame, 0.08)
	_update_feedback()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _skill != null:
		configure(_skill, _target)

func _update_feedback() -> void:
	var highlighted: bool = not disabled and (is_hovered() or has_focus())
	var tint: Color = Color.WHITE if not disabled else Color("748195")
	if _motion != null: _motion.kill()
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(content, "modulate", tint, hover_duration)
	_motion.tween_property(action_label, "modulate", _accent if highlighted else Color("acbacb"), hover_duration)

func _press_feedback() -> void:
	if disabled: return
	if _motion != null: _motion.kill()
	_motion = create_tween()
	_motion.tween_property(content, "modulate", Color("bacadd"), hover_duration * 0.5)

func _style_frame(frame: PanelContainer, opacity: float) -> void:
	var source: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat
	var style: StyleBoxFlat = source.duplicate() as StyleBoxFlat
	style.bg_color = Color(_accent, opacity)
	style.border_color = Color(_accent, 0.4)
	frame.add_theme_stylebox_override("panel", style)

func _ignore_child_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		if child is Control: _ignore_child_mouse(child as Control)
