class_name UnlockLineSupplyEffect
extends ChoiceEffect

## 0 = row sweeper, 1 = column sweeper (LineClearState axes).
@export var axis: int = 0

func rejection(context: ChoiceEffectContext) -> String:
	if axis == LineClearState.AXIS_ROW and context.line_row_unlocked: return "已解锁行清除补给"
	if axis == LineClearState.AXIS_COLUMN and context.line_column_unlocked: return "已解锁列清除补给"
	if axis != LineClearState.AXIS_ROW and axis != LineClearState.AXIS_COLUMN: return "扫线轴向无效"
	if context.empty_coordinates.is_empty(): return "没有空格"
	return ""

func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.coordinate = context.empty_coordinates[(random.randi_range(0, context.empty_coordinates.size() - 1) if context.empty_coordinates.size() > 1 else 0)]
	target.color = SpawnState.sample_color(context.color_weights, random)
	target.line_index = axis
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.UNLOCK_LINE
	request.coordinate = target.coordinate
	request.color = target.color
	request.stat = axis
	request.error = rejection(context)
	if not request.error.is_empty(): return request
	if target.color < 0 or target.color >= context.color_weights.size(): request.error = "扫线手预告颜色无效"
	elif not context.empty_coordinates.has(target.coordinate): request.error = "原定空格已经被占用"
	return request
