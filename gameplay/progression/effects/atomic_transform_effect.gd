class_name AtomicTransformEffect
extends TransformMaterialEffect

## Testable atomic boundary: consume ordinary unmarked material and convert an exact target batch.
## No catalog entry is installed by this effect definition.
@export var material_cost: int = 1

func rejection(context: ChoiceEffectContext) -> String:
	if material_cost < 1: return "转化成本配置无效"
	var reason: String = super.rejection(context)
	if not reason.is_empty(): return reason
	return "转化材料不足" if _candidates(context).size() < count + material_cost else ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	if not rejection(context).is_empty(): return SkillTarget.new()
	var target: SkillTarget = super.freeze(context, random)
	for id: int in _candidates(context):
		if target.piece_ids.has(id): continue
		target.cost_piece_ids.append(id)
		if target.cost_piece_ids.size() == material_cost: break
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = super.build(context, target)
	if not request.error.is_empty(): return request
	if target.piece_ids.size() != count or target.cost_piece_ids.size() != material_cost:
		request.error = "原子转化必须满足完整成本与目标"
		return request
	var legal: Array[int] = _candidates(context)
	for id: int in target.cost_piece_ids:
		if not legal.has(id) or request.piece_ids.has(id) or request.cost_piece_ids.has(id):
			request.error = "原子转化成本已经失效"
			return request
		request.cost_piece_ids.append(id)
	return request
