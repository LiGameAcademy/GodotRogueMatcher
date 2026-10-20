class_name TransformMaterialEffect
extends ChoiceEffect

## Freeze ordinary, unmarked sources without replacement; application changes content only.
@export var content_id: StringName
@export_range(1, 3) var count: int = 3
## Composite later leaves may explicitly select from the remaining ordinary material.
@export var reselect_after_previous: bool = false

func dynamic_targets() -> bool:
	return reselect_after_previous or super.dynamic_targets()

func rejection(context: ChoiceEffectContext) -> String:
	if content_id not in [&"special_demolition", LineClearState.CONTENT_ROW, LineClearState.CONTENT_COLUMN] or count < 1 or count > 3:
		return "特殊棋转化配置无效"
	return "没有可转化的普通棋子" if _candidates(context).is_empty() else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	if not rejection(context).is_empty(): return target
	var ids: Array[int] = _candidates(context)
	for _index: int in range(mini(count, ids.size())):
		var index: int = random.randi_range(0, ids.size() - 1)
		target.piece_ids.append(ids[index])
		ids.remove_at(index)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.TRANSFORM
	request.content_id = content_id
	request.error = rejection(context)
	if not request.error.is_empty(): return request
	if target == null or target.piece_ids.is_empty() or target.piece_ids.size() > count:
		request.error = "转化目标数量无效"
		return request
	var legal: Array[int] = _candidates(context)
	for id: int in target.piece_ids:
		if not legal.has(id) or request.piece_ids.has(id):
			request.error = "原定转化目标已经失效"
			return request
		request.piece_ids.append(id)
	return request

func _candidates(context: ChoiceEffectContext) -> Array[int]:
	var ids: Array[int] = []
	for piece: PieceState in context.material:
		if piece.content_id.is_empty() and not piece.is_ghost and not context.ability_piece_ids.has(piece.piece_id):
			ids.append(piece.piece_id)
	return ids
