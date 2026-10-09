class_name InstallDyeUpgradeEffect
extends ChoiceEffect

@export var upgrade: StringName

func rejection(context: ChoiceEffectContext) -> String:
	return "等级已达安全上限" if context.dye_upgrades.get(upgrade, 0) >= 1000000 else ""

func freeze(context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.value_before = context.dye_upgrades.get(upgrade, 0)
	target.value_after = target.value_before + 1
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.DYE_UPGRADE
	request.upgrade = upgrade
	if context.dye_upgrades.get(upgrade, 0) != target.value_before or target.value_after != target.value_before + 1:
		request.error = "升级目标已失效"
	return request

