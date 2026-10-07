class_name RefillCountEffect
extends ChoiceEffect

@export var delta: int = -1
@export var batches: int = 3

func rejection(context: ChoiceEffectContext) -> String:
	if delta not in [-1, 1] or batches <= 0: return "补棋效果参数无效"
	var count: int = context.next_refill + (delta if context.refill_batches[delta] == 0 else 0)
	if count < context.spawn_config.minimum_refill or count > context.spawn_config.maximum_refill:
		return "下次补棋数量已到边界"
	return ""

func freeze(context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.value_before = context.next_refill
	target.value_after = context.next_refill + (delta if context.refill_batches[delta] == 0 else 0)
	target.remaining_before = context.refill_batches[delta]
	target.remaining_after = target.remaining_before + batches
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.error = rejection(context)
	var expected: SkillTarget = freeze(context, null)
	if context.next_refill != target.value_before or target.value_after != expected.value_after or target.remaining_before != expected.remaining_before or target.remaining_after != expected.remaining_after:
		request.error = "原定补棋数量已经失效"
	request.kind = ChoiceEffectRequest.Kind.REFILL
	request.delta = delta
	request.batches = batches
	return request
