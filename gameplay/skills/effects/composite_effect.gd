class_name CompositeEffect
extends SkillEffect

## Ordered SkillEffect children. Leaf1 commits before leaf2 selects/builds.
enum FixedTargetPolicy { REJECT, SKIP_INVALID }

@export var children: Array[SkillEffect] = []
## REJECT fails the whole acquire; SKIP_INVALID drops dead fixed ids and may yield a legal empty leaf.
@export var fixed_target_policy: FixedTargetPolicy = FixedTargetPolicy.REJECT

func validation_error(ancestors: Array[SkillEffect] = []) -> String:
	if children.is_empty(): return "composite effect missing children"
	if ancestors.has(self): return "composite effect cycle"
	if ancestors.size() >= MAX_EFFECT_DEPTH: return "composite effect nested too deep"
	var next: Array[SkillEffect] = ancestors.duplicate()
	next.append(self)
	for child: SkillEffect in children:
		if child == null: return "composite effect child missing"
		if child is ChoiceEffect:
			continue
		if child is CompositeEffect:
			var error: String = child.validation_error(next)
			if not error.is_empty(): return error
			continue
		return "unsupported composite child effect"
	return ""

func rejection(context: ChoiceEffectContext) -> String:
	var error: String = validation_error()
	if not error.is_empty(): return error
	for child: SkillEffect in children:
		if child is ChoiceEffect:
			error = (child as ChoiceEffect).rejection(context)
		elif child is CompositeEffect:
			error = (child as CompositeEffect).rejection(context)
		if not error.is_empty(): return error
	return ""

## Freeze every leaf against the current context for offer preview and leaf0 apply.
func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> CompositeSkillTarget:
	var target: CompositeSkillTarget = CompositeSkillTarget.new()
	for child: SkillEffect in children:
		if child is ChoiceEffect:
			target.leaf_targets.append((child as ChoiceEffect).freeze(context, random))
		elif child is CompositeEffect:
			target.leaf_targets.append((child as CompositeEffect).freeze(context, random))
	return target

## Refresh nested previews without discarding child-specific frozen choices.
func refresh_after_previous(context: ChoiceEffectContext, frozen: CompositeSkillTarget, random: RandomNumberGenerator) -> CompositeSkillTarget:
	var target: CompositeSkillTarget = CompositeSkillTarget.new()
	if frozen == null or frozen.leaf_targets.size() != children.size(): return target
	for index: int in range(children.size()):
		var child: SkillEffect = children[index]
		var previous: SkillTarget = frozen.leaf_targets[index]
		if child is ChoiceEffect:
			target.leaf_targets.append((child as ChoiceEffect).refresh_after_previous(context, previous, random))
		elif child is CompositeEffect:
			target.leaf_targets.append((child as CompositeEffect).refresh_after_previous(context, previous as CompositeSkillTarget, random))
	return target

func requires_color_choice() -> bool:
	for child: SkillEffect in children:
		if child is ChoiceEffect and (child as ChoiceEffect).requires_color_choice():
			return true
		if child is CompositeEffect and (child as CompositeEffect).requires_color_choice():
			return true
	return false
