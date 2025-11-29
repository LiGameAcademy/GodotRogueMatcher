extends UIForm
class_name GameForm

@onready var score_container: HBoxContainer = %ScoreContainer

var number_textures = [
	preload("res://assets/textures/widgets/numbers/number0.png"), 
	preload("res://assets/textures/widgets/numbers/number1.png"), 
	preload("res://assets/textures/widgets/numbers/number2.png"), 
	preload("res://assets/textures/widgets/numbers/number3.png"), 
	preload("res://assets/textures/widgets/numbers/number4.png"), 
	preload("res://assets/textures/widgets/numbers/number5.png"), 
	preload("res://assets/textures/widgets/numbers/number6.png"), 
	preload("res://assets/textures/widgets/numbers/number7.png"), 
	preload("res://assets/textures/widgets/numbers/number8.png"), 
	preload("res://assets/textures/widgets/numbers/number9.png")
]

## 更新分数显示 
func update_score_display(current_score: int) -> void:
	var score_str : String = str(current_score)
	var digit_count = score_str.length()
	for i in range(digit_count):
		var digit = int(score_str[i])
		var digit_sprite : TextureRect
		if score_container.get_child_count() <= i:
			digit_sprite = TextureRect.new()
			score_container.add_child(digit_sprite)
		else:
			digit_sprite = score_container.get_child(i)
		digit_sprite.texture = number_textures[digit]
