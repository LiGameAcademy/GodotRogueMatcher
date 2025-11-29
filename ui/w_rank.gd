extends MarginContainer

#var t_medalGold = preload("res://assets/textures/widgets/icons/medalGold.png")
#var t_medalSilver = preload("res://assets/textures/widgets/icons/medalSilver.png")
#var t_medalBronze = preload("res://assets/textures/widgets/icons/medalBronze.png")

@onready var tr_medal: TextureRect = %tr_medal
@onready var lab_name: Label = %lab_name
@onready var lab_score: Label = %lab_score
@onready var lab_empty: Label = %lab_empty
@onready var margin_container: MarginContainer = %MarginContainer

@export var medal_texture : Texture = null

func _ready() -> void:
	tr_medal.texture = medal_texture

func update_rank(name: String, score: int) -> void:
	if score != 0 and score != null:
		lab_empty.hide()
		margin_container.show()
		lab_name.text = "name: " + name
		lab_score.text = "score: " + str(score)
	else:
		lab_empty.show()
		margin_container.hide()
