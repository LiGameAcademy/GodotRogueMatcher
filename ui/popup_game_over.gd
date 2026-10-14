class_name PopupGameOver
extends Control

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
