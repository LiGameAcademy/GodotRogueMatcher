class_name ChoiceEffect
extends Resource

## 单叶子选择效果契约：查询快照、冻结目标、生成请求；提交由SkillRules负责。
func requires_color_choice() -> bool:
	return false

func rejection(_context: ChoiceEffectContext) -> String:
	return "选择效果缺少实现"

func freeze(_context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	return SkillTarget.new()

func build(_context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.error = "选择效果缺少实现"
	return request
