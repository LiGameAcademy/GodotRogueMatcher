class_name CompositeSkillTarget
extends SkillTarget

## Frozen per-leaf targets aligned with CompositeEffect.children order.
var leaf_targets: Array[SkillTarget] = []

func copy() -> SkillTarget:
	var result: CompositeSkillTarget = CompositeSkillTarget.new()
	_copy_into(result)
	for leaf: SkillTarget in leaf_targets: result.leaf_targets.append(leaf.copy() if leaf != null else null)
	return result

func color_picker_source() -> SkillTarget:
	for leaf: SkillTarget in leaf_targets:
		if leaf != null and not leaf.color_groups.is_empty():
			return leaf
	return self
