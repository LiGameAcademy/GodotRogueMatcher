class_name AssignFuseEffect
extends ChoiceEffect

func _init() -> void:
	target_policy = TargetPolicy.DYNAMIC

## Random unmarked materials gain fuses; capacity is 2 + fuse_capacity upgrade.

func rejection(context: ChoiceEffectContext) -> String:
	return "没有可赋引信的普通棋子" if _candidates(context).is_empty() else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	var ids: Array[int] = _candidates(context)
	var count: int = mini(2 + context.upgrades.get(&"fuse_capacity", 0), ids.size())
	for _index: int in range(count):
		var chosen: int = (random.randi_range(0, ids.size() - 1) if ids.size() > 1 else 0)
		target.piece_ids.append(ids[chosen])
		ids.remove_at(chosen)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.ASSIGN_FUSE
	var legal: Array[int] = _candidates(context)
	var maximum: int = 2 + context.upgrades.get(&"fuse_capacity", 0)
	if target.piece_ids.is_empty() or target.piece_ids.size() > maximum:
		request.error = "材料目标配置无效"
		return request
	var unique: Array[int] = []
	for id: int in target.piece_ids:
		if not legal.has(id) or unique.has(id):
			request.error = "原定材料目标已经失效"
			return request
		unique.append(id)
	request.piece_ids = unique
	return request

func _candidates(context: ChoiceEffectContext) -> Array[int]:
	var ids: Array[int] = []
	for piece: PieceState in context.material:
		if not context.fuse_ids.has(piece.piece_id):
			ids.append(piece.piece_id)
	return ids

func build_surviving(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	if target.piece_ids.size() > 2 + context.upgrades.get(&"fuse_capacity", 0): return build(context, target)
	var kept: SkillTarget = target.copy()
	kept.piece_ids.clear()
	var legal: Array[int] = _candidates(context)
	var seen: Array[int] = []
	for id: int in target.piece_ids:
		if seen.has(id): return build(context, target)
		seen.append(id)
		if legal.has(id): kept.piece_ids.append(id)
	if not kept.piece_ids.is_empty(): return build(context, kept)
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.ASSIGN_FUSE
	return request
