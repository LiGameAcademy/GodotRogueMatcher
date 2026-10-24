class_name SkillCard
extends Button

## 独立卡面只消费定义和冻结目标，选择仍由弹窗提交命令。
@onready var card_back: Panel = $CardBack
@onready var rarity_label: Label = %Rarity
@onready var kind_label: Label = %Kind
@onready var consume_label: RichTextLabel = %Consumable
@onready var title_label: Label = %Title
@onready var level_label: Label = %Level
@onready var effect_label: RichTextLabel = %Effect
@onready var preview_label: Label = %Preview
@onready var flavor_label: Label = %Flavor
@onready var action_label: Label = %Action
@onready var content: MarginContainer = $Content
@export var hover_duration: float = 0.12
var _reveal: Tween
var _selected: bool = false
var _motion: Tween
var _accent: Color = Color.WHITE
var _skill: SkillDefinition
var _catalog_run: RunController
var _target: SkillTarget
var _game_theme: GameTheme

func apply_game_theme(preset: GameTheme) -> void:
	_game_theme = preset
	if _skill == null: return
	_accent = SkillRarity.color_for(_skill.rarity, preset)
	SkillRarity.style(self, _skill.rarity, preset)
	rarity_label.add_theme_color_override("font_color", _accent)
	set_selected(_selected)

func _ready() -> void:
	_ignore_child_mouse(content)
	mouse_entered.connect(_update_feedback)
	mouse_exited.connect(_update_feedback)
	focus_entered.connect(_update_feedback)
	focus_exited.connect(_update_feedback)
	button_down.connect(_press_feedback)
	button_up.connect(_update_feedback)
	content.minimum_size_changed.connect(_fit_catalog_height)

func _exit_tree() -> void:
	if _motion != null: _motion.kill()
	if _reveal != null: _reveal.kill()

func configure(skill: SkillDefinition, target: SkillTarget) -> void:
	finish_reveal()
	_selected = false
	_catalog_run = null
	action_label.show()
	focus_mode = Control.FOCUS_ALL
	_skill = skill
	_target = target
	_accent = SkillRarity.color_for(skill.rarity, _game_theme)
	SkillRarity.style(self, skill.rarity, _game_theme)
	rarity_label.text = tr(SkillRarity.NAMES[skill.rarity])
	rarity_label.add_theme_color_override("font_color", _accent)
	kind_label.text = SkillChoiceText.tags(skill)
	kind_label.visible = not kind_label.text.is_empty()
	consume_label.visible = skill.refill_effect() != null
	consume_label.text = tr("消耗")
	consume_label.tooltip_text = tr(SkillChoiceText.CONSUME_HINT)
	title_label.text = tr(skill.title)
	level_label.text = SkillChoiceText.level_text(skill, target)
	level_label.visible = not level_label.text.is_empty()
	effect_label.text = SkillChoiceText.summary_rich(skill)
	flavor_label.text = tr(skill.flavor_text) if not skill.flavor_text.is_empty() else ""
	flavor_label.visible = not flavor_label.text.is_empty()
	preview_label.text = SkillChoiceText.compact_preview(skill, target)
	preview_label.visible = not preview_label.text.is_empty()
	action_label.text = tr("点选后，在下方确认")
	_update_feedback()

## 技能池只读卡面，不冻结随机目标或提供选取动作。
func configure_catalog(skill: SkillDefinition, run: RunController) -> void:
	configure(skill, SkillTarget.new())
	_catalog_run = run
	_target = null
	level_label.hide()
	var details: PackedStringArray = SkillPoolText.details(run, skill).split("\n")
	var effect_lines: int = SkillChoiceText.summary(skill).split("\n").size()
	preview_label.text = "\n".join(details.slice(effect_lines))
	preview_label.show()
	action_label.hide()
	focus_mode = Control.FOCUS_NONE
	_fit_catalog_height.call_deferred()

## UI-only selection state; catalog cards remain read-only.
func set_selected(selected: bool) -> void:
	_selected = selected
	var box: StyleBoxFlat = get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	box.border_color = _accent if selected else Color(_accent, 0.65)
	box.set_border_width_all(3 if selected else 2)
	if _game_theme != null:
		box.set_border_width_all(2 if selected else 1)
		box.border_width_top = 3
	add_theme_stylebox_override("normal", box)
	if _catalog_run == null: action_label.text = tr("已点选 · 等待确认") if selected else tr("点选后，在下方确认")
	_update_feedback()

func reveal(delay: float, low_effects: bool) -> void:
	finish_reveal()
	if low_effects: return
	pivot_offset = size * 0.5
	scale.x = 1.0
	content.hide()
	card_back.add_theme_stylebox_override("panel", get_theme_stylebox("normal").duplicate())
	card_back.show()
	_reveal = create_tween()
	_reveal.tween_interval(delay)
	_reveal.tween_property(self, "scale:x", 0.04, 0.10)
	_reveal.tween_callback(func() -> void: card_back.hide(); content.show())
	_reveal.tween_property(self, "scale:x", 1.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func finish_reveal() -> void:
	if _reveal != null: _reveal.kill()
	scale = Vector2.ONE
	modulate = Color.WHITE
	if is_node_ready():
		card_back.hide()
		content.show()

func set_presentation_only() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_ignore_child_mouse(content, true)

func _fit_catalog_height() -> void:
	if _catalog_run == null: return
	custom_minimum_size.y = maxf(360.0, content.get_combined_minimum_size().y + 36.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _skill != null:
		if _catalog_run != null: configure_catalog(_skill, _catalog_run)
		else: configure(_skill, _target)

func _update_feedback() -> void:
	var highlighted: bool = not disabled and (is_hovered() or has_focus() or _selected)
	var tint: Color = Color.WHITE if not disabled else Color("748195")
	if _motion != null: _motion.kill()
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(content, "modulate", tint, hover_duration)
	_motion.tween_property(action_label, "modulate", Color.WHITE if highlighted else Color("acbacb"), hover_duration)

func _press_feedback() -> void:
	if disabled or _catalog_run != null: return
	if _motion != null: _motion.kill()
	_motion = create_tween()
	_motion.tween_property(content, "modulate", Color("bacadd"), hover_duration * 0.5)

func _ignore_child_mouse(node: Control, presentation_only: bool = false) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_PASS if not presentation_only and (node == effect_label or node == consume_label) else Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		if child is Control: _ignore_child_mouse(child as Control, presentation_only)
