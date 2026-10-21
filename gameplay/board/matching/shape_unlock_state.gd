class_name ShapeUnlockState
extends RefCounted

## One board in one run owns both enabled identities and their acquisition roots.
var _templates: Dictionary[StringName, MatchShapeTemplate] = {}
var _roots: Dictionary[StringName, int] = {}
var recovery_pending: bool = false
var recovery_attempted: bool = false
var recovery_root: int = 0
var recovery_batch_id: int = 0
var recovery_action_id: int = 0

func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_templates.keys())
	result.sort()
	return result

func templates() -> Array[MatchShapeTemplate]:
	var result: Array[MatchShapeTemplate] = []
	for id: StringName in ids(): result.append(_templates[id].duplicate(true) as MatchShapeTemplate)
	return result

func contains(id: StringName) -> bool:
	return _templates.has(id)

func unlock(template: MatchShapeTemplate, root: int) -> bool:
	if template == null or not template.validation_error().is_empty() or contains(template.shape_id): return false
	_templates[template.shape_id] = template.duplicate(true) as MatchShapeTemplate
	_roots[template.shape_id] = root
	if not recovery_pending:
		recovery_pending = true
		recovery_attempted = false
		recovery_root = root
	return true

func data() -> Dictionary:
	var enabled: Array[Dictionary] = []
	for id: StringName in ids():
		enabled.append({"shape_id": id, "offsets": _templates[id].offsets.duplicate(), "root": _roots[id]})
	return {"enabled": enabled, "recovery_pending": recovery_pending, "recovery_attempted": recovery_attempted, "recovery_root": recovery_root, "recovery_batch_id": recovery_batch_id, "recovery_action_id": recovery_action_id}
