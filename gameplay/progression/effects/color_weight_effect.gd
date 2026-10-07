class_name ColorWeightEffect
extends ChoiceEffect

@export var delta: int = 2

func rejection(context: ChoiceEffectContext) -> String:
	if delta == 0: return "颜色权重增量不能为零"
	return "没有可调整的颜色" if _eligible(context).is_empty() else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var colors: Array[int] = _eligible(context)
	var target: SkillTarget = SkillTarget.new()
	target.color = colors[random.randi_range(0, colors.size() - 1)]
	target.value_before = context.color_weights[target.color]
	target.value_after = target.value_before + delta
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.COLOR_WEIGHT
	request.color = target.color
	request.delta = delta
	if not _eligible(context).has(target.color): request.error = "原定颜色不能调整"
	elif context.color_weights[target.color] != target.value_before or target.value_after != target.value_before + delta:
		request.error = "原定颜色权重已经失效"
	return request

func _eligible(context: ChoiceEffectContext) -> Array[int]:
	var colors: Array[int] = []
	for color: int in range(context.color_weights.size()):
		var weight: int = context.color_weights[color] + delta
		if weight >= context.spawn_config.minimum_weight and weight <= context.spawn_config.maximum_weight:
			colors.append(color)
	return colors
