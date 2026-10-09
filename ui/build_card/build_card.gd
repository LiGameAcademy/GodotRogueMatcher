extends PanelContainer

## 已取得技能的只读横卡；不提交选择或查找外部节点。
@onready var title_label: Label = %Title
@onready var metadata_label: Label = %Metadata
@onready var level_label: Label = %Level
@onready var effect_label: RichTextLabel = %Effect
@onready var remaining_label: Label = %Remaining

func configure(skill: SkillDefinition, level: int, remaining: int) -> void:
	title_label.text = tr(skill.title)
	var tags: String = SkillChoiceText.tags(skill)
	metadata_label.text = tr(SkillRarity.NAMES[skill.rarity])
	if not tags.is_empty(): metadata_label.text += " · " + tags
	metadata_label.add_theme_color_override("font_color", SkillRarity.COLORS[skill.rarity])
	level_label.text = "Lv.%d" % level
	level_label.visible = skill.is_persistent
	effect_label.text = SkillChoiceText.summary_rich(skill)
	remaining_label.visible = skill.choice_effect is RefillCountEffect
	remaining_label.text = tr("剩余 %d 次实际补棋") % remaining
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = SkillRarity.COLORS[skill.rarity]
	add_theme_stylebox_override("panel", style)

