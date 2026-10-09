class_name SkillCard
extends Button

## 独立卡面只消费定义和冻结目标，选择仍由弹窗提交命令。
@onready var rarity_label: Label = %Rarity
@onready var kind_label: Label = %Kind
@onready var consume_label: RichTextLabel = %Consumable
@onready var title_label: Label = %Title
@onready var level_label: Label = %Level
@onready var effect_label: RichTextLabel = %Effect
@onready var preview_label: Label = %Preview
@onready var action_label: Label = %Action
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
	rarity_label.text = tr(SkillRarity.NAMES[skill.rarity])
	rarity_label.add_theme_color_override("font_color", _accent)
	kind_label.text = SkillChoiceText.tags(skill)
	kind_label.visible = not kind_label.text.is_empty()
	consume_label.visible = skill.choice_effect is RefillCountEffect
	consume_label.text = tr("消耗")
	consume_label.tooltip_text = tr(SkillChoiceText.CONSUME_HINT)
	title_label.text = tr(skill.title)
	level_label.text = SkillChoiceText.level_text(skill, target)
	level_label.visible = not level_label.text.is_empty()
	effect_label.text = SkillChoiceText.summary_rich(skill)
	preview_label.text = SkillChoiceText.compact_preview(skill, target)
	preview_label.visible = not preview_label.text.is_empty()
	action_label.text = tr("点击选择颜色") if skill.choice_effect != null and skill.choice_effect.requires_color_choice() else tr("点击选择此技能")
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
	_motion.tween_property(action_label, "modulate", Color.WHITE if highlighted else Color("acbacb"), hover_duration)

func _press_feedback() -> void:
	if disabled: return
	if _motion != null: _motion.kill()
	_motion = create_tween()
	_motion.tween_property(content, "modulate", Color("bacadd"), hover_duration * 0.5)

func _ignore_child_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_PASS if node == effect_label or node == consume_label else Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		if child is Control: _ignore_child_mouse(child as Control)
