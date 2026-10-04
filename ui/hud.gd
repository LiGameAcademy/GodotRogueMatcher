extends Control
class_name hud

@onready var score_label: Label = %ScoreLabel

func _ready() -> void:
	GameManager.score_changed.connect(
		func(new_score : float): score_label.text = "分数：" + str(new_score)
	)
