class_name PopupSkillChoice
extends Control

signal skill_selected(offer_id: int, skill_id: StringName)
signal color_skill_selected(offer_id: int, skill_id: StringName, color: int)
signal skill_pool_requested
signal settings_requested
signal card_acquired(skill: SkillDefinition, target: SkillTarget, source: Rect2)
signal closed

@onready var confirm_button: Button = %ConfirmSelection
@onready var heading: Label = $Center/Panel/Column/Heading
@onready var message: Label = $Center/Panel/Column/Message
@onready var options: HBoxContainer = $Center/Panel/Column/Options
@onready var picker: ColorTargetPicker = $Center/Panel/Column/ColorTargetPicker
@onready var center: CenterContainer = $Center
@onready var backdrop: ColorRect = $Backdrop
@onready var view_button: Button = $Center/Panel/Column/Tools/ViewButton
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
var _low_effects: bool = false
var _reason: String = ""
var _error: String = ""

func _ready() -> void:
	for index: int in range(options.get_child_count()):
		var button: SkillCard = options.get_child(index) as SkillCard
		button.pressed.connect(_select.bind(index))
	confirm_button.pressed.connect(confirm_selection)
	picker.color_chosen.connect(_update_confirmation)
	picker.confirm_button.hide()
	picker.back_requested.connect(return_to_choices)
	%SkillPoolButton.pressed.connect(skill_pool_requested.emit)
	%SettingsButton.pressed.connect(settings_requested.emit)
	view_button.pressed.connect(toggle_board_view)
	return_button.pressed.connect(toggle_board_view)
	resume_button.pressed.connect(toggle_selection_pause)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and offer != null:
		_refresh_text()

func _refresh_text() -> void:
	heading.text = tr("目标达成 · 第%d次选择") % offer.reward_id
	message.text = tr(_reason) if not _reason.is_empty() else tr("选择一项技能，继续你的构筑")
	if _target_index >= 0 and offer.choices[_target_index].requires_color_choice():
		var skill: SkillDefinition = offer.choices[_target_index]
		heading.text = tr("%s · 选择颜色") % tr(skill.title)
		message.text = SkillChoiceText.summary(skill)
	if not _error.is_empty(): message.text = tr(_error)
	var target: String = ""
	if _target_index >= 0 and offer.choices[_target_index].requires_color_choice():
		target = tr(" · 尚未选色") if picker.selected_color == -1 else tr(" · 已选") + tr(PieceTooltip.COLOR_NAMES[picker.selected_color])
	return_label.text = tr("正在选择技能%s · 棋盘仅供查看") % target
	_update_confirmation()

func initialize(data: Dictionary = {}) -> void:
	var value: Variant = data.get("offer")
	if not value is SkillOffer:
		push_error("技能弹窗需要有效候选")
		return
	show_offer(value)

func show_offer(next_offer: SkillOffer, reason: String = "") -> void:
	offer = next_offer.snapshot()
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
		button.visible = index < offer.choices.size()
		button.disabled = not button.visible
		if not button.visible: continue
		var skill: SkillDefinition = offer.choices[index]
		button.configure(skill, offer.targets[skill.skill_id])
		button.set_unavailable(offer.unavailable.get(skill.skill_id, ""))
	_update_visibility()
	_update_confirmation()
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
	_update_confirmation()

## 仅收起表现；SceneTree仍暂停，规则仍处于REWARDS。
func toggle_board_view() -> void:
	if _submitted or selection_paused: return
	viewing_board = not viewing_board
	var target: String = ""
	if _target_index >= 0 and offer.choices[_target_index].requires_color_choice():
		target = tr(" · 尚未选色") if picker.selected_color == -1 else tr(" · 已选") + tr(PieceTooltip.COLOR_NAMES[picker.selected_color])
	return_label.text = tr("正在选择技能%s · 棋盘仅供查看") % target
	_update_confirmation()
	_update_visibility()
	if viewing_board: return_button.grab_focus()
	else: view_button.grab_focus()

func toggle_selection_pause() -> void:
	if _submitted: return
	selection_paused = not selection_paused
	_update_visibility()
	if selection_paused: resume_button.grab_focus()

func accept_selection(animate_acquired: bool = false) -> void:
	if _closed: return
	_closed = true
	if animate_acquired and _submitted and _target_index >= 0:
		var skill: SkillDefinition = offer.choices[_target_index]
		var card: SkillCard = options.get_child(_target_index) as SkillCard
		card_acquired.emit(skill, offer.targets[skill.skill_id], card.get_global_rect())
	_finish_close()

## 普通关闭不确认选择；暂停与恢复入口由Game协调。
func close_view() -> void:
	if _closed: return
	_closed = true
	_finish_close()

func _finish_close() -> void:
	hide()
	closed.emit()
	queue_free()

func show_error(reason: String) -> void:
	_error = reason
	message.text = tr(reason)
	_submitted = false
	if _target_index >= 0 and offer.choices[_target_index].requires_color_choice(): picker.show_error(reason)
	for index: int in range(options.get_child_count()):
		(options.get_child(index) as Button).disabled = index >= offer.choices.size() or offer.unavailable.has(offer.choices[index].skill_id)
	picker.confirm_button.disabled = false
	picker.back_button.disabled = false
	view_button.disabled = false
	_update_confirmation()

func set_unavailable(reasons: Dictionary[StringName, String]) -> void:
	offer.unavailable.assign(reasons)
	for index: int in range(offer.choices.size()):
		(options.get_child(index) as SkillCard).set_unavailable(offer.unavailable.get(offer.choices[index].skill_id, ""))
	_update_confirmation()

## A card click only changes the pending UI selection, never applies a skill.
func _select(index: int) -> void:
	if _submitted or offer == null or viewing_board or selection_paused or index < 0 or index >= offer.choices.size(): return
	if offer.unavailable.has(offer.choices[index].skill_id): return
	_target_index = index
	_error = ""
	var skill: SkillDefinition = offer.choices[index]
	var target: SkillTarget = offer.targets[skill.skill_id]
	if skill.requires_color_choice(target.level_before):
		picker.configure(target)
		options.hide()
		picker.show()
	else:
		picker.hide()
	_refresh_text()
	_update_confirmation()

## One shared button at the bottom commits both ordinary and color-target choices.
func confirm_selection() -> void:
	if _submitted or offer == null or _target_index < 0 or viewing_board or selection_paused: return
	var skill: SkillDefinition = offer.choices[_target_index]
	if offer.unavailable.has(skill.skill_id): return
	if skill.requires_color_choice(offer.targets[skill.skill_id].level_before):
		if picker.selected_color == -1:
			picker.show_error("请先选择颜色", false)
			return
		_submit(_target_index, picker.selected_color)
	else:
		_submit(_target_index)

func _update_confirmation(_color: int = -1) -> void:
	confirm_button.disabled = _submitted or _target_index < 0
	if _target_index >= 0 and offer.unavailable.has(offer.choices[_target_index].skill_id): confirm_button.disabled = true
	confirm_button.text = tr("请先点选一张卡片") if _target_index < 0 else tr("确认选择：%s") % tr(offer.choices[_target_index].title)
	if _target_index >= 0 and offer.choices[_target_index].requires_color_choice():
		confirm_button.disabled = confirm_button.disabled or picker.selected_color == -1
	for index: int in range(options.get_child_count()):
		(options.get_child(index) as SkillCard).set_selected(index == _target_index)

func set_low_effects(enabled: bool) -> void:
	_low_effects = enabled
	if enabled:
		for card: SkillCard in options.get_children(): card.finish_reveal()

func _submit(index: int, color: int = -1) -> void:
	if _submitted or viewing_board or selection_paused: return
	_submitted = true
	confirm_button.disabled = true
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
	for index: int in range(options.get_child_count()):
		var card: SkillCard = options.get_child(index) as SkillCard
		card.reveal(float(index) * 0.045, _low_effects)
