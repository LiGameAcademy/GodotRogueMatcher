extends PanelContainer

## 已取得技能的只读横卡；不提交选择或查找外部节点。
@onready var title_label: Label = %Title
@onready var metadata_label: Label = %Metadata
@onready var level_label: Label = %Level
@onready var effect_label: RichTextLabel = %Effect
@onready var remaining_label: Label = %Remaining
var _game_theme: GameTheme
var _rarity: SkillDefinition.Rarity = SkillDefinition.Rarity.COMMON

func apply_game_theme(preset: GameTheme) -> void:
	_game_theme = preset
	var style: StyleBoxFlat = preset.ui_theme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
	style.border_color = SkillRarity.color_for(_rarity, preset)
	style.border_width_left = 3
	add_theme_stylebox_override("panel", style)
	metadata_label.add_theme_color_override("font_color", style.border_color)

func configure(skill: SkillDefinition, level: int, remaining: int, manual_remaining: int = -1) -> void:
	_rarity = skill.rarity
	title_label.text = tr(skill.title)
	var tags: String = SkillChoiceText.tags(skill)
	metadata_label.text = tr(SkillRarity.NAMES[skill.rarity])
	if not tags.is_empty(): metadata_label.text += " · " + tags
	metadata_label.add_theme_color_override("font_color", SkillRarity.COLORS[skill.rarity])
	level_label.text = "Lv.%d" % level
	level_label.visible = skill.is_persistent
	effect_label.text = SkillChoiceText.summary_rich(skill)
	remaining_label.visible = skill.refill_effect() != null or skill.manual_use_limit > 0
	remaining_label.text = tr("剩余 %d 次实际补棋") % remaining
	if skill.manual_use_limit > 0:
		if manual_remaining >= 0:
			remaining_label.text = tr("主动剩余 %d / %d 次") % [manual_remaining, skill.manual_use_limit]
		else:
			remaining_label.text = tr("本局可主动 %d 次") % skill.manual_use_limit
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = SkillRarity.COLORS[skill.rarity]
	add_theme_stylebox_override("panel", style)
	if _game_theme != null: apply_game_theme(_game_theme)

