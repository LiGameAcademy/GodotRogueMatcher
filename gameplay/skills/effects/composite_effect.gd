class_name CompositeEffect
extends SkillEffect

## Ordered SkillEffect children. Leaf1 commits before leaf2 selects/builds.
enum FixedTargetPolicy { REJECT, SKIP_INVALID }

@export var children: Array[SkillEffect] = []
## REJECT fails the whole acquire; SKIP_INVALID drops dead fixed ids and may yield a legal empty leaf.
@export var fixed_target_policy: FixedTargetPolicy = FixedTargetPolicy.REJECT
## An entirely empty acquire needs an explicit root declaration as well as legal empty leaves.
@export var allow_empty_acquisition: bool = false

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
	if not allow_empty_acquisition and empty_targets_allowed(context): return "组合没有可生效目标"
	return _child_rejection(context)

func _child_rejection(context: ChoiceEffectContext) -> String:
	var error: String = ""
	for child: SkillEffect in children:
		if child is ChoiceEffect:
			error = (child as ChoiceEffect).rejection(context)
		elif child is CompositeEffect:
			error = (child as CompositeEffect)._child_rejection(context)
		if not error.is_empty(): return error
	return ""

func empty_targets_allowed(context: ChoiceEffectContext) -> bool:
	if children.is_empty(): return false
	for child: SkillEffect in children:
		if child is ChoiceEffect:
			var choice: ChoiceEffect = child as ChoiceEffect
			# A fixed leaf may still repaint to a color no longer present on the board.
			if not choice.dynamic_targets() or not choice.empty_targets_allowed(context): return false
		if child is CompositeEffect and not (child as CompositeEffect).empty_targets_allowed(context): return false
	return true

## Fixed leaves freeze identities; dynamic leaves store only their deferred contract.
func freeze(context: ChoiceEffectContext, random: RandomNumberGenerator) -> CompositeSkillTarget:
	var target: CompositeSkillTarget = CompositeSkillTarget.new()
	for child: SkillEffect in children:
		if child is ChoiceEffect:
			target.leaf_targets.append((child as ChoiceEffect).freeze_offer(context, random))
		elif child is CompositeEffect:
			target.leaf_targets.append((child as CompositeEffect).freeze(context, random))
	return target

func requires_color_choice() -> bool:
	for child: SkillEffect in children:
		if child is ChoiceEffect and (child as ChoiceEffect).requires_color_choice():
			return true
		if child is CompositeEffect and (child as CompositeEffect).requires_color_choice():
			return true
	return false
