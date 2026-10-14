class_name InstallLineUpgradeEffect
extends ChoiceEffect

@export var upgrade: StringName
## -1 accepts either supply; span upgrades require their own axis.
@export var required_axis: int = -1

func rejection(context: ChoiceEffectContext) -> String:
	if required_axis not in [-1, LineClearState.AXIS_ROW, LineClearState.AXIS_COLUMN]: return "扫线轴向无效"
	if required_axis == LineClearState.AXIS_ROW and not context.line_row_unlocked: return "需先获得行清除手登场"
	if required_axis == LineClearState.AXIS_COLUMN and not context.line_column_unlocked: return "需先获得列清除手登场"
	if not context.line_row_unlocked and not context.line_column_unlocked: return "需先获得行或列清除手登场"
	return "等级已达安全上限" if context.line_upgrades.get(upgrade, 0) >= 1000000 else ""

func freeze(context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.value_before = context.line_upgrades.get(upgrade, 0)
	target.value_after = target.value_before + 1
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.LINE_UPGRADE
	request.upgrade = upgrade
	request.error = rejection(context)
	if request.error.is_empty() and (context.line_upgrades.get(upgrade, 0) != target.value_before or target.value_after != target.value_before + 1):
		request.error = "升级目标已失效"
	return request
