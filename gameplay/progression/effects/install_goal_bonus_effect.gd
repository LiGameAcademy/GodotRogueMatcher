class_name InstallGoalBonusEffect
extends ChoiceEffect

## 试调数值由卡牌Resource提供；本局安装值不回写配置。
@export var bonus_score: int = 25

func rejection(context: ChoiceEffectContext) -> String:
	if not context.stage_enabled: return "仅阶段挑战可用"
	if bonus_score <= 0: return "目标奖励分必须为正数"
	return "已满级" if context.goal_bonus_score > 0 else ""

func freeze(context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.value_before = context.goal_bonus_score
	target.value_after = bonus_score
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.GOAL_BONUS
	request.score_bonus = bonus_score
	request.error = rejection(context)
	if context.goal_bonus_score != target.value_before or target.value_after != bonus_score:
		request.error = "目标奖励配置已失效"
	return request
