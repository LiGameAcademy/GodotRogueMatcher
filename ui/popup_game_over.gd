extends Control

signal retry_requested
signal menu_requested

@onready var score_label: Label = $Panel/Content/ScoreLabel
@onready var retry_button: Button = $Panel/Content/RetryButton
@onready var summary_label: Label = $Panel/Content/SummaryLabel

func _ready() -> void:
	retry_button.pressed.connect(_on_retry_pressed)
	($Panel/Content/MenuButton as Button).pressed.connect(menu_requested.emit)

func initialize(data: Dictionary = {}) -> void:
	var score_value: Variant = data.get("score", 0)
	if score_value is int:
		score_label.text = "本局得分：%d" % int(score_value)
	var summary_value: Variant = data.get("summary", "")
	if summary_value is String: summary_label.text = String(summary_value)
	retry_button.grab_focus()

func _on_retry_pressed() -> void:
	retry_button.disabled = true
	retry_requested.emit()
