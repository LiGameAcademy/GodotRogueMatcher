extends GameplayEffect
class_name EffectAddScore

## 增加分数效果

## 分数倍数（1.0 = 100%，0.5 = 50%）
@export var score_multiplier: float = 1.0

## 固定分数加成
@export var fixed_bonus: int = 0

func _init(multiplier: float = 1.0, bonus: int = 0) -> void:
	effect_id = "add_score"
	score_multiplier = multiplier
	fixed_bonus = bonus

func apply(context: Dictionary = {}) -> bool:
	var base_score: int = context.get("score", 0)
	var bonus_score: int = int(base_score * score_multiplier) + fixed_bonus
	
	if bonus_score > 0:
		GameManager.add_score(bonus_score)
		print("效果 [", effect_id, "] 应用：增加 ", bonus_score, " 分")
		return true
	
	return false

func get_description() -> String:
	var desc: String = ""
	if score_multiplier > 0:
		desc += "分数 +" + str(int(score_multiplier * 100)) + "%"
	if fixed_bonus > 0:
		if desc != "":
			desc += " + "
		desc += str(fixed_bonus) + " 分"
	return desc

