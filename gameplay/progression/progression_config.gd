class_name ProgressionConfig
extends Resource

## 累计分数门槛；超过表格后继续递增，不设强制通关或失败条件。
@export var milestones: Array[int] = [100, 250, 500, 900, 1500, 2400, 3700, 5500, 8000, 11500]
@export var tail_multiplier: float = 1.5

func threshold(index: int) -> int:
	if index < milestones.size(): return milestones[index]
	var score: int = milestones.back()
	for step: int in range(index - milestones.size() + 1):
		score = maxi(score + 1, int(ceil(score * tail_multiplier)))
	return score
