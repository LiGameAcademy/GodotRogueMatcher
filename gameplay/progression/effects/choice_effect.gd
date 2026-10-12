class_name ChoiceEffect
extends SkillEffect

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
