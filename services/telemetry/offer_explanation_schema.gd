extends RefCounted

## Validates frozen unified-offer telemetry without loading gameplay or consuming RNGs.
static func validate(data: Dictionary) -> String:
	for field: String in ["explanations", "build_snapshot", "parameters"]:
		if not data.get(field) is Dictionary: return "missing_unified_offer_" + field
	if not data.get("slots") is Array or data.explanations.is_empty(): return "missing_unified_offer_slots"
	for field: String in ["related_gain", "gap_gain", "factor_min", "factor_max"]:
		if not data.parameters.get(field) is float or not is_finite(data.parameters[field]): return "invalid_offer_parameter"
	for id: Variant in data.explanations:
		if not id is String or not data.explanations[id] is Dictionary: return "invalid_candidate_explanation"
		var row: Dictionary = data.explanations[id]
		for field: String in ["H", "related", "fills_gap"]:
			if row.get(field) not in ["0", "1"]: return "invalid_binary_weight_factor"
		if not row.get("rejection") is String: return "invalid_candidate_rejection"
		if (row.H == "1") != row.rejection.is_empty(): return "inconsistent_candidate_eligibility"
		for field: String in ["B", "Q", "s", "V", "factor_before_clamp", "factor_after_clamp", "weight_before_clamp", "W"]:
			if not row.get(field) is float or not is_finite(row[field]): return "invalid_numeric_weight_factor"
		if row.B <= 0.0 or row.Q <= 0.0 or row.W < 0.0: return "invalid_weight_bounds"
		if row.H == "0" and (row.W != 0.0 or row.fills_gap != "0"): return "ineligible_candidate_has_weight"
		var before: float = 1.0 + data.parameters.related_gain * int(row.related) + data.parameters.gap_gain * int(row.fills_gap) + row.s
		if not is_equal_approx(before, row.factor_before_clamp): return "inconsistent_additive_factor"
		if not is_equal_approx(clampf(before, data.parameters.factor_min, data.parameters.factor_max), row.factor_after_clamp): return "inconsistent_clamped_factor"
		var expected: float = int(row.H) * row.B * row.Q * row.factor_after_clamp * row.V
		if not is_equal_approx(row.W, expected): return "inconsistent_final_weight"
	var used: Array[String] = []
	for slot: Variant in data.slots:
		if not slot is Dictionary or not slot.get("weights") is Dictionary: return "invalid_slot_weights"
		if not slot.get("denominator") is float or not is_finite(slot.denominator): return "invalid_slot_denominator"
		if not slot.get("sampled") is bool: return "invalid_slot_sample_flag"
		var denominator: float = 0.0
		var ids: Array = slot.weights.keys()
		ids.sort()
		for id: Variant in ids:
			if not id is String or used.has(id) or not slot.weights[id] is float or not is_finite(slot.weights[id]) or slot.weights[id] <= 0.0:
				return "invalid_slot_member"
			if not data.explanations.has(id) or data.explanations[id].H != "1" or not is_equal_approx(slot.weights[id], data.explanations[id].W):
				return "slot_weight_disagrees_with_candidate"
			denominator += slot.weights[id]
		if not is_equal_approx(denominator, slot.denominator): return "inconsistent_slot_denominator"
		if ids.is_empty():
			if slot.get("selected") != null or slot.get("sample") != null or slot.sampled: return "invalid_empty_slot"
			continue
		if slot.sampled != (ids.size() > 1) or not slot.get("sample") is float or slot.sample < 0.0 or slot.sample >= 1.0:
			return "invalid_slot_sample"
		if not slot.get("selected") is String: return "invalid_slot_selection"
		var accumulated: float = 0.0
		var selected: String = ""
		for id: String in ids:
			accumulated += slot.weights[id]
			if accumulated > slot.sample * denominator:
				selected = id
				break
		if slot.get("selected") != selected: return "inconsistent_slot_selection"
		used.append(selected)
	if not data.get("generation_order") is Array or used != data.generation_order: return "inconsistent_generation_order"
	if not data.get("choices") is Array or data.choices.size() < 1 or data.choices.size() > 3 or data.choices.size() != used.size():
		return "invalid_unified_choices"
	var displayed: Array[String] = []
	for id: Variant in data.choices:
		if not id is String or displayed.has(id) or not used.has(id): return "inconsistent_unified_choices"
		displayed.append(id)
	if not data.get("weights") is Dictionary or data.weights.size() != data.explanations.size(): return "invalid_unified_weights"
	for id: Variant in data.explanations:
		if not data.weights.get(id) is float or not is_equal_approx(data.weights[id], data.explanations[id].W):
			return "inconsistent_unified_weights"
	return ""
