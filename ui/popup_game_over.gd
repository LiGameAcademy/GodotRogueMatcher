extends Control

signal retry_requested

@onready var score_label: Label = $Panel/Content/ScoreLabel
@onready var retry_button: Button = $Panel/Content/RetryButton

func _ready() -> void:
	retry_button.pressed.connect(_on_retry_pressed)

func initialize(data: Dictionary = {}) -> void:
	var score_value: Variant = data.get("score", 0)
	if score_value is int:
		score_label.text = "本局得分：%d" % int(score_value)
	retry_button.grab_focus()

func _on_retry_pressed() -> void:
	retry_button.disabled = true
	retry_requested.emit()
