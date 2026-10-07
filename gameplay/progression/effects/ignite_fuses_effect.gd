class_name IgniteFusesEffect
extends ChoiceEffect

func rejection(context: ChoiceEffectContext) -> String:
	return "没有引信棋子" if context.fuse_ids.is_empty() else ""

func freeze(context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.piece_ids = context.fuse_ids.duplicate()
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.CLEAR
	if target.piece_ids != context.fuse_ids or target.piece_ids.is_empty():
		request.error = "引信目标已失效"
	request.piece_ids = target.piece_ids.duplicate()
	return request
