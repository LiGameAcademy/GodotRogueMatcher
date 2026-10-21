class_name ThinMaterialEffect
extends ChoiceEffect

func _init() -> void:
	target_policy = TargetPolicy.DYNAMIC

## Instantly remove up to `count` unmarked ordinary pieces without scoring.
@export var count: int = 3

func rejection(context: ChoiceEffectContext) -> String:
	return "没有可疏整材料" if _candidates(context).is_empty() else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	var ids: Array[int] = _candidates(context)
	var take: int = mini(maxi(count, 0), ids.size())
	for _index: int in range(take):
		var chosen: int = random.randi_range(0, ids.size() - 1)
		target.piece_ids.append(ids[chosen])
		ids.remove_at(chosen)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.THIN
	var legal: Array[int] = _candidates(context)
	var maximum: int = maxi(count, 0)
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
