class_name PopupSkillChoice
extends Control

signal skill_selected(offer_id: int, skill_id: StringName)
signal color_skill_selected(offer_id: int, skill_id: StringName, color: int)
signal skill_pool_requested
signal closed

@onready var heading: Label = $Center/Panel/Column/Heading
@onready var message: Label = $Center/Panel/Column/Message
@onready var options: HBoxContainer = $Center/Panel/Column/Options
@onready var picker: ColorTargetPicker = $Center/Panel/Column/ColorTargetPicker
@onready var center: CenterContainer = $Center
@onready var backdrop: ColorRect = $Backdrop
@onready var view_button: Button = $Center/Panel/Column/ViewButton
@onready var return_bar: PanelContainer = $ReturnBar
@onready var return_label: Label = $ReturnBar/Row/Message
@onready var return_button: Button = $ReturnBar/Row/Return
@onready var pause_panel: CenterContainer = $PausePanel
@onready var resume_button: Button = $PausePanel/Panel/Column/Resume
var offer: SkillOffer
var viewing_board: bool = false
var selection_paused: bool = false
var _target_index: int = -1
var _submitted: bool = false
var _closed: bool = false
var _entrance: Tween
var _reason: String = ""
var _error: String = ""

func _ready() -> void:
	for index: int in range(options.get_child_count()):
		var button: SkillCard = options.get_child(index) as SkillCard
		button.pressed.connect(_select.bind(index))
	picker.confirmed.connect(_confirm_color)
	picker.back_requested.connect(return_to_choices)
	%SkillPoolButton.pressed.connect(skill_pool_requested.emit)
	view_button.pressed.connect(toggle_board_view)
	return_button.pressed.connect(toggle_board_view)
	resume_button.pressed.connect(toggle_selection_pause)

func _exit_tree() -> void:
	if _entrance != null: _entrance.kill()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and offer != null:
		_refresh_text()

func _refresh_text() -> void:
	heading.text = tr("目标达成 · 第%d次选择") % offer.reward_id
	message.text = tr(_reason) if not _reason.is_empty() else tr("选择一项技能，继续你的构筑")
	if _target_index >= 0:
		var skill: SkillDefinition = offer.choices[_target_index]
		heading.text = tr("%s · 选择颜色") % tr(skill.title)
		message.text = SkillChoiceText.summary(skill)
	if not _error.is_empty(): message.text = tr(_error)
	var target: String = ""
	if _target_index >= 0:
		target = tr(" · 尚未选色") if picker.selected_color == -1 else tr(" · 已选") + tr(PieceTooltip.COLOR_NAMES[picker.selected_color])
	return_label.text = tr("正在选择技能%s · 棋盘仅供查看") % target

func initialize(data: Dictionary = {}) -> void:
	var value: Variant = data.get("offer")
	if not value is SkillOffer:
		push_error("技能弹窗需要有效候选")
		return
	show_offer(value)
	get_tree().paused = true

func show_offer(next_offer: SkillOffer, reason: String = "") -> void:
	offer = next_offer
	_reason = reason
	_error = ""
	_submitted = false
	_target_index = -1
	viewing_board = false
	selection_paused = false
	picker.hide()
	options.show()
	heading.text = tr("目标达成 · 第%d次选择") % offer.reward_id
	message.text = tr(reason) if not reason.is_empty() else tr("选择一项技能，继续你的构筑")
	for index: int in range(options.get_child_count()):
		var button: SkillCard = options.get_child(index) as SkillCard
		button.disabled = index >= offer.choices.size()
		if button.disabled: continue
		var skill: SkillDefinition = offer.choices[index]
		button.configure(skill, offer.targets[skill.skill_id])
	_update_visibility()
	_animate_cards()

func return_to_choices() -> void:
	if _submitted: return
	_target_index = -1
	_error = ""
	_reason = ""
	picker.hide()
	options.show()
	heading.text = tr("目标达成 · 第%d次选择") % offer.reward_id
	message.text = tr("选择一项技能，继续你的构筑")

## 仅收起表现；SceneTree仍暂停，规则仍处于REWARDS。
func toggle_board_view() -> void:
	if _submitted or selection_paused: return
	viewing_board = not viewing_board
	var target: String = ""
	if _target_index >= 0:
		target = tr(" · 尚未选色") if picker.selected_color == -1 else tr(" · 已选") + tr(PieceTooltip.COLOR_NAMES[picker.selected_color])
	return_label.text = tr("正在选择技能%s · 棋盘仅供查看") % target
	_update_visibility()
	if viewing_board: return_button.grab_focus()
	else: view_button.grab_focus()

func toggle_selection_pause() -> void:
	if _submitted: return
	selection_paused = not selection_paused
	_update_visibility()
	if selection_paused: resume_button.grab_focus()

func accept_selection() -> void:
	if _closed: return
	_closed = true
	get_tree().paused = false
	hide()
	closed.emit()
	queue_free()

func show_error(reason: String) -> void:
	_error = reason
	message.text = tr(reason)
	_submitted = false
	if _target_index >= 0: picker.show_error(reason)
	for index: int in range(options.get_child_count()):
		(options.get_child(index) as Button).disabled = index >= offer.choices.size()
	picker.confirm_button.disabled = false
	picker.back_button.disabled = false
	view_button.disabled = false

func _select(index: int) -> void:
	if _submitted or offer == null or viewing_board or selection_paused or index < 0 or index >= offer.choices.size(): return
	var skill: SkillDefinition = offer.choices[index]
	if skill.choice_effect != null and skill.choice_effect.requires_color_choice():
		_error = ""
		_target_index = index
		picker.configure(offer.targets[skill.skill_id])
		options.hide()
		picker.show()
		heading.text = tr("%s · 选择颜色") % tr(skill.title)
		message.text = SkillChoiceText.summary(skill)
		return
	_submit(index)

func _confirm_color(color: int) -> void:
	if _target_index >= 0: _submit(_target_index, color)

func _submit(index: int, color: int = -1) -> void:
	if _submitted or viewing_board or selection_paused: return
	_submitted = true
	for button: Button in options.get_children(): button.disabled = true
	picker.confirm_button.disabled = true
	picker.back_button.disabled = true
	view_button.disabled = true
	if color == -1: skill_selected.emit(offer.offer_id, offer.choices[index].skill_id)
	else: color_skill_selected.emit(offer.offer_id, offer.choices[index].skill_id, color)

func _update_visibility() -> void:
	center.visible = not viewing_board and not selection_paused
	backdrop.visible = not viewing_board or selection_paused
	return_bar.visible = viewing_board and not selection_paused
	pause_panel.visible = selection_paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE if viewing_board and not selection_paused else Control.MOUSE_FILTER_STOP

func _animate_cards() -> void:
	if _entrance != null: _entrance.kill()
	_entrance = create_tween().set_parallel(true)
	for index: int in range(options.get_child_count()):
		var card: SkillCard = options.get_child(index) as SkillCard
		card.modulate.a = 0.0
		_entrance.tween_property(card, "modulate:a", 1.0, 0.18).set_delay(float(index) * 0.045)
