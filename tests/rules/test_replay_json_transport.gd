extends GutTest

## Seed 1046's real v46 slot sample exposes the second-rounding boundary.
const SAMPLE_BYTES: String = "00000000082d0e3f"

func _record() -> Dictionary:
	return {"offer": {"slots": [{"sample": SAMPLE_BYTES.hex_decode().decode_double(0), "sampled": true, "selected": "assign_fuse", "slot": "0"}]}, "rng": {"state": "9223372036854775807"}}

func test_short_json_round_trip_matches_exact_persistence_projection() -> void:
	var actual: Dictionary = _record()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(actual, "", true))
	assert_ne(RunSnapshot.canonical(persisted), RunSnapshot.canonical(actual), "fixture must expose real second rounding")
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay._record_matches(actual, actual, true))
	assert_true(replay._record_matches(persisted, actual, true))
	assert_false(replay._record_matches(persisted, actual, false), "full-precision segments cannot use the short legacy projection")

func test_projection_does_not_accept_modified_sample_candidate_structure_or_random_identity() -> void:
	var actual: Dictionary = _record()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(actual, "", true))
	var replay: RuleReplay = RuleReplay.new()
	for field: String in ["sample", "selected", "sampled", "slot", "rng", "extra", "missing"]:
		var changed: Dictionary = persisted.duplicate(true)
		match field:
			"sample": changed.offer.slots[0].sample += 0.000000000001
			"selected": changed.offer.slots[0].selected = "score_multiplier"
			"sampled": changed.offer.slots[0].sampled = false
			"slot": changed.offer.slots[0].slot = 0.0
			"rng": changed.rng.state = "9223372036854775806"
			"extra": changed.offer.slots.append(changed.offer.slots[0].duplicate(true))
			"missing": changed.offer.erase("slots")
		assert_false(replay._record_matches(changed, actual, true), field)

func test_full_precision_and_zero_values_keep_direct_semantics() -> void:
	var actual: Dictionary = _record()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(actual, "", true, true))
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay._record_matches(persisted, actual, false))
	assert_false(replay._record_matches({"value": 0.0}, {"value": 0.000000000000001}, true))

