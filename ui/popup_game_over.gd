class_name PopupGameOver
extends Control

const PORTRAIT: PackedScene = preload("res://ui/preparation_room/role_portrait.tscn")
const PROGRESS: Script = preload("res://services/run_checkpoint/opening_progress.gd")
const ROLE: Script = preload("res://gameplay/openings/opening_role.gd")

signal continue_requested
signal retry_requested
signal menu_requested

@onready var title_label: Label = $Panel/Content/Title
@onready var score_label: Label = $Panel/Content/ScoreLabel
@onready var continue_button: Button = $Panel/Content/ContinueButton
@onready var completion_label: Label = $Panel/Content/CompletionLabel
@onready var retry_button: Button = $Panel/Content/RetryButton
@onready var summary_label: Label = $Panel/Content/SummaryLabel
@onready var collection_controls: CollectionControls = $Panel/Content/CollectionControls
var _final_score: int = 0
var _run_state: RunState

func _ready() -> void:
	retry_button.pressed.connect(_on_retry_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	($Panel/Content/MenuButton as Button).pressed.connect(menu_requested.emit)

func initialize(data: Dictionary = {}) -> void:
	var score_value: Variant = data.get("score", 0)
	if score_value is int:
		_final_score = int(score_value)
		score_label.text = tr("本局得分：%d") % _final_score
	var state_value: Variant = data.get("run_state")
	if state_value is RunState:
		_run_state = state_value as RunState
		title_label.text = StageText.end_title(_run_state)
	var summary_value: Variant = data.get("summary", "")
	if summary_value is String: summary_label.text = String(summary_value)
	continue_button.visible = data.get("can_continue", false) is bool and bool(data.get("can_continue", false))
	completion_label.visible = _run_state != null and _run_state.end_reason == &"challenge_completed"
	if completion_label.visible:
		completion_label.text = tr("已完成全部 %d 个阶段。") % _run_state.stage.config.targets.size()
	if continue_button.visible: continue_button.grab_focus()
	else: retry_button.grab_focus()
	if data.get("progress") != null: show_progress(data.progress)
	if data.get("opening_unlocked", false): show_opening_unlock(data.joined)
	elif continue_button.visible: retry_button.hide()

func show_progress(progress: PROGRESS) -> void:
	var best_label: Label = $Panel/Content/PersonalBest
	best_label.text = tr("role.best") % progress.best
	var role: ROLE = progress.next_locked()
	if role != null:
		best_label.text = tr("role.next") % tr("role." + str(role.id)) + "\n" + tr("role.target") % [progress.best, role.threshold, role.threshold - progress.best]
	best_label.show()

func show_opening_unlock(joined: Array[StringName]) -> void:
	var banner: Label = $Panel/Content/OpeningUnlock
	if banner.visible: return
	var ids: Array[StringName] = joined.duplicate()
	if ids.is_empty(): ids.append(&"row_sweep")
	for id: StringName in ids:
		var role: ROLE = RunController.ROLES.find(id)
		var card: VBoxContainer = VBoxContainer.new()
		var face: TextureRect = PORTRAIT.instantiate()
		var name_label: Label = Label.new()
		name_label.text = tr("role.joined") % tr("role." + str(id))
		card.add_child(face)
		card.add_child(name_label)
		$Panel/Content/Portraits.add_child(card)
		face.display(role)
	banner.text = tr("role.where")
	($Panel/Content/MenuButton as Button).text = tr("role.enter_room")
	banner.show()
	continue_button.hide()
	retry_button.hide()
	($Panel/Content/MenuButton as Button).grab_focus()

func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready(): return
	score_label.text = tr("本局得分：%d") % _final_score
	if _run_state != null:
		summary_label.text = HudDetails.summary(_run_state)
		title_label.text = StageText.end_title(_run_state)
		if completion_label.visible: completion_label.text = tr("已完成全部 %d 个阶段。") % _run_state.stage.config.targets.size()

func _on_continue_pressed() -> void:
	continue_button.disabled = true
	retry_button.disabled = true
	continue_requested.emit()

func _on_retry_pressed() -> void:
	retry_button.disabled = true
	retry_requested.emit()
