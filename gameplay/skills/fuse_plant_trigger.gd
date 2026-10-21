class_name FusePlantTrigger
extends RefCounted

var centers: Array[Vector2i] = []
var radius: int = 0
var count: int = 0
var trace: Dictionary = {}

static func capture(results: Array[MatchResult]) -> FusePlantTrigger:
	var trigger: FusePlantTrigger = FusePlantTrigger.new()
	trigger.radius = DemolitionRules.CONFIG.plant_radius
	trigger.count = DemolitionRules.CONFIG.plant_count
	for result: MatchResult in results:
		for piece: PieceState in result.removed: trigger.centers.append(piece.coordinate)
	trigger.trace = {"kind": "match_plant", "source_score_event_id": results[0].score_entry.event_id, "centers": trigger.centers.duplicate(), "radius": trigger.radius, "count": trigger.count, "status": "pending", "actual_ids": []}
	results[0].followups.append(trigger.trace)
	return trigger

func execute(resolver: AbilityResolver) -> void:
	if trace.status != "pending": return
	trace.actual_ids = DemolitionRules.mark_near(resolver, centers, radius, count)
	trace.status = "empty" if trace.actual_ids.is_empty() else "applied"

func cancel() -> void:
	if trace.status == "pending":
		trace.status = "interrupted"
		trace.reason = "composite_aborted"
