extends RefCounted

## Retains only facts consumed by OfferMeasurements, after full source validation/export.
static func compact(event: Dictionary) -> Dictionary:
	var payload: Dictionary = event.payload
	match event.event_name:
		"offer_generated":
			var explanations: Dictionary = {}
			for id: String in payload.get("explanations", {}):
				var row: Dictionary = payload.explanations[id]
				explanations[id] = {"H": row.H, "rejection": row.rejection}
			payload = {"offer_id": payload.offer_id, "reward_id": payload.reward_id,
				"choices": payload.choices.duplicate(), "explanations": explanations,
				"offer_rules_version": payload.get("offer_rules_version"), "replaces_offer_id": payload.get("replaces_offer_id", "0")}
		"offer_presented": payload = {"offer_id": payload.offer_id}
		"skill_acquired":
			payload = {"offer_id": payload.offer_id, "skill_id": payload.skill_id, "reward_id": payload.get("reward_id")}
		"command_resolved":
			if payload.type != "choose" or payload.accepted: return {}
			payload = {"type": payload.type, "accepted": false}
		_: return {}
	var result: Dictionary = event.duplicate(false)
	result.payload = payload
	return result
