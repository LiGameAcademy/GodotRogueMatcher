class_name UnlockShapeEffect
extends ChoiceEffect

@export var template: MatchShapeTemplate

func rejection(context: ChoiceEffectContext) -> String:
	if template == null: return "missing shape template"
	var error: String = template.validation_error()
	if not error.is_empty(): return error
	if context.unlocked_shapes.has(template.shape_id): return "shape already unlocked"
	return ""

func build(context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.UNLOCK_SHAPE
	request.error = rejection(context)
	request.shape_template = template
	return request
