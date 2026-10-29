class_name UnlockCoreSupplyEffect
extends ChoiceEffect

## 取得时解锁供给并落首枚；先完整预检，提交仍由规则入口负责。
func rejection(context: ChoiceEffectContext) -> String:
	if context.core_pool_unlocked: return "已解锁核心供给"
	if context.empty_coordinates.is_empty(): return "没有空格"
	if context.core_present: return "爆壳手仍在场"
	return ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.coordinate = context.empty_coordinates[(random.randi_range(0, context.empty_coordinates.size() - 1) if context.empty_coordinates.size() > 1 else 0)]
	target.color = SpawnState.sample_color(context.color_weights, random)
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.UNLOCK_CORE
	request.coordinate = target.coordinate
	request.color = target.color
	request.error = rejection(context)
	if not request.error.is_empty(): return request
	if target.color < 0 or target.color >= context.color_weights.size(): request.error = "爆破手预告颜色无效"
	elif not context.empty_coordinates.has(target.coordinate): request.error = "原定空格已经被占用"
	return request
