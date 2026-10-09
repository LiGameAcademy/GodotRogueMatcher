extends ScrollContainer

const CARD: PackedScene = preload("res://ui/build_card/build_card.tscn")
const CARD_SCRIPT: Script = preload("res://ui/build_card/build_card.gd")
@onready var cards: VBoxContainer = %Cards
@onready var empty_label: Label = %Empty
var _cards: Dictionary[StringName, PanelContainer] = {}

## 仅刷新展示，复用相同技能的横卡以保留滚动位置。
func show_state(state: RunState) -> void:
	var active: Array[SkillDefinition] = HudDetails.active_skills(state)
	var ids: Array[StringName] = []
	for index: int in range(active.size()):
		var skill: SkillDefinition = active[index]
		ids.append(skill.skill_id)
		if not _cards.has(skill.skill_id):
			var created: PanelContainer = CARD.instantiate() as PanelContainer
			cards.add_child(created)
			_cards[skill.skill_id] = created
		var card: CARD_SCRIPT = _cards[skill.skill_id] as CARD_SCRIPT
		card.configure(skill, SkillRules.level(state, skill), HudDetails.remaining_refills(skill, state))
		cards.move_child(card, index)
	for id: StringName in _cards.keys():
		if ids.has(id): continue
		var retired: PanelContainer = _cards[id]
		cards.remove_child(retired)
		retired.queue_free()
		_cards.erase(id)
	empty_label.visible = active.is_empty()
	empty_label.text = tr("尚未获得持续技能")

