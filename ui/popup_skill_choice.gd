class_name PopupSkillChoice
extends Control

signal skill_selected(offer_id: int, skill_id: StringName)
signal closed

@onready var heading: Label = $Center/Panel/Column/Heading
@onready var message: Label = $Center/Panel/Column/Message
@onready var options: HBoxContainer = $Center/Panel/Column/Options
var offer: SkillOffer
var _submitted: bool = false
var _closed: bool = false

func _ready() -> void:
	for index: int in range(options.get_child_count()):
		var button: Button = options.get_child(index) as Button
		button.pressed.connect(_select.bind(index))

func initialize(data: Dictionary = {}) -> void:
	var value: Variant = data.get("offer")
	if not value is SkillOffer:
		push_error("技能弹窗需要有效候选")
		return
	show_offer(value)
	get_tree().paused = true

func show_offer(next_offer: SkillOffer, reason: String = "") -> void:
	offer = next_offer
	_submitted = false
	heading.text = "目标达成 · 第%d次选择" % offer.reward_id
	message.text = reason if not reason.is_empty() else "选择一项技能，继续你的构筑"
	for index: int in range(options.get_child_count()):
		var button: Button = options.get_child(index) as Button
		button.disabled = false
		var skill: SkillDefinition = offer.choices[index]
		button.text = "%s\n\n%s" % [skill.title, skill.description]

## 应用是否成功由规则协调器决定，点击本身不关闭或扣除奖励。
func _select(index: int) -> void:
	if _submitted or offer == null: return
	_submitted = true
	for button: Button in options.get_children(): button.disabled = true
	skill_selected.emit(offer.offer_id, offer.choices[index].skill_id)

func accept_selection() -> void:
	if _closed: return
	_closed = true
	get_tree().paused = false
	hide()
	closed.emit()
	queue_free()

func show_error(reason: String) -> void:
	message.text = reason
	_submitted = false
	for button: Button in options.get_children(): button.disabled = false
