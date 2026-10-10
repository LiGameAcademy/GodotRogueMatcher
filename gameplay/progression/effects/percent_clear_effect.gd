class_name PercentClearEffect
extends ChoiceEffect

## 只读比例配置；使用奖励目标随机流，不影响普通补棋。
@export_range(0.0, 1.0) var ratio: float = 0.25

func rejection(context: ChoiceEffectContext) -> String:
	if not is_finite(ratio) or ratio <= 0.0 or ratio > 1.0:
		return "比例清理配置无效"
	return "没有足够的普通棋子" if floori(context.material.size() * ratio) == 0 else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	if not rejection(context).is_empty(): return target
	var remaining: Array[int] = []
	for piece: PieceState in context.material: remaining.append(piece.piece_id)
	target.value_before = remaining.size()
	var count: int = floori(remaining.size() * ratio)
	for index: int in range(count):
		var chosen: int = random.randi_range(0, remaining.size() - 1)
		target.piece_ids.append(remaining[chosen])
		remaining.remove_at(chosen)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.CLEAR
	request.error = rejection(context)
	if not request.error.is_empty(): return request
	if target.value_before != context.material.size() or target.piece_ids.size() != floori(context.material.size() * ratio):
		request.error = "原定清理目标已经失效"
		return request
	var legal: Array[int] = []
	for piece: PieceState in context.material: legal.append(piece.piece_id)
	for id: int in target.piece_ids:
		if not legal.has(id) or request.piece_ids.has(id):
			request.error = "原定清理目标已经失效"
			return request
		request.piece_ids.append(id)
	return request
