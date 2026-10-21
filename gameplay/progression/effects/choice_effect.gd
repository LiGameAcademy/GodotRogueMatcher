class_name ChoiceEffect
extends SkillEffect

enum TargetPolicy { FIXED, DYNAMIC }
@export var target_policy: TargetPolicy = TargetPolicy.FIXED

func dynamic_targets() -> bool:
	return target_policy == TargetPolicy.DYNAMIC

func empty_targets_allowed(_context: ChoiceEffectContext) -> bool:
	return false

## Dynamic contracts have no sampled identities at offer time.
func freeze_offer(context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
	if not dynamic_targets(): return freeze(context, random)
	var target: SkillTarget = SkillTarget.new()
	target.deferred = true
	return target

## Single-leaf acquire effect: query snapshot, freeze targets, build request; SkillRules/AbilityEffectRunner commit.
func requires_color_choice() -> bool:
	return false

func rejection(_context: ChoiceEffectContext) -> String:
	return "choice effect is not implemented"

func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	return SkillTarget.new()

func build(_context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.error = "choice effect is not implemented"
	return request

## Unsupported partial applications retain their original diagnostic.
func build_surviving(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	return build(context, target)

## 固定目标默认保留；只有明确声明动态选择的叶子才在到达时重选。
func refresh_after_previous(_context: ChoiceEffectContext, frozen: SkillTarget, _random: RandomNumberGenerator) -> SkillTarget:
	return frozen
