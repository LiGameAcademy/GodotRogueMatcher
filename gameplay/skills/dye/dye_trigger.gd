class_name DyeTrigger
extends RefCounted

## Per-trigger source and scalar strength; live targets are selected only at execution.
var centers: Array[Vector2i] = []
var color: int = -1
var radius: int = 1
var orthogonal: bool = true
var target_count: int = 1
var maximum_waves: int = 1
var kind: StringName = &"match_dye"
var source: MatchResult
var trace: Dictionary = {}
var alternatives: Array[DyeTrigger] = []

func record() -> void:
	trace = {"kind": kind, "source_score_event_id": source.score_entry.event_id, "centers": centers.duplicate(), "color": color, "radius": radius, "orthogonal": orthogonal, "target_count": target_count, "maximum_waves": maximum_waves, "status": "pending", "actual_ids": []}
	source.followups.append(trace)

func execute(resolver: AbilityResolver) -> Array[MatchResult]:
	var candidates: Array[DyeTrigger] = [self]
	candidates.append_array(alternatives)
	var results: Array[MatchResult] = []
	for candidate: DyeTrigger in candidates:
		if not results.is_empty():
			candidate.trace.status = "batch_not_selected"
			continue
		results = candidate._execute_one(resolver)
	return results

func _execute_one(resolver: AbilityResolver) -> Array[MatchResult]:
	if trace.status != "pending": return []
	if resolver.state.dye.waves_used >= maximum_waves:
		trace.status = "wave_limit"
		return []
	var ids: Array[int] = DyeRules.targets(resolver.state, centers, color, radius, orthogonal)
	ids.resize(mini(ids.size(), target_count))
	trace.actual_ids = ids.duplicate()
	trace.status = "empty" if ids.is_empty() else "applied"
	if ids.is_empty(): return []
	return DyeRules.wave(resolver, ids, color, maximum_waves)

func cancel(reason: String = "composite_aborted") -> void:
	if trace.status == "pending":
		trace.status = "interrupted"
		trace.reason = reason
	for alternative: DyeTrigger in alternatives: alternative.cancel(reason)
