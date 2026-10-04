extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var board: Board = $Board

func _ready() -> void:
	GameManager.game_overed.connect(_on_game_over)

func _on_game_over() -> void:
	board.can_selected = false
	var popup: Control = await UIManager.open_popup("popup_game_over", {"score": GameManager.score})
	if is_instance_valid(popup):
		popup.retry_requested.connect(_on_retry_requested)

func _on_retry_requested() -> void:
	UIManager.close_popup()
	await board.retry_game()
