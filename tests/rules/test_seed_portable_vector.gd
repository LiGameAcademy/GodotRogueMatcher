extends GutTest

## Locks #161 portable vector against known sl-rng-v1 derivation; not a cross-OS claim by itself.
const VECTOR: Script = preload("res://services/run_random/seed_portable_vector.gd")

func test_build_matches_known_stream_seeds_and_is_stable() -> void:
	var vector: Dictionary = VECTOR.build(42, 8)
	assert_eq(vector.protocol, VECTOR.PROTOCOL)
	assert_eq(vector.rng_scheme_version, RunRandomStreams.SCHEME_VERSION)
	assert_eq(vector.master_seed, "42")
	assert_eq(vector.draws, 8)
	var expected: Array = [2698757283641008609, 4156300916487032238, 8284178283302528712, 978293449253142013, 7461956290973307042, 7474628424099629659]
	for index: int in range(RunRandomStreams.IDS.size()):
		var id: String = String(RunRandomStreams.IDS[index])
		assert_eq(vector.streams[id].seed, str(expected[index]))
		assert_eq(vector.first_draws[id].size(), 8)
	assert_eq(VECTOR.gameplay_mismatch(vector, VECTOR.build(42, 8)), "")

func test_mismatch_detects_seed_and_draw_drift_without_platform_noise() -> void:
	var baseline: Dictionary = VECTOR.build(0, 4)
	var other_seed: Dictionary = VECTOR.build(1, 4)
	assert_eq(VECTOR.gameplay_mismatch(baseline, other_seed), "field_mismatch:master_seed")
	var tampered: Dictionary = baseline.duplicate(true)
	tampered.platform = "OtherOS"
	tampered.godot = "future"
	assert_eq(VECTOR.gameplay_mismatch(baseline, tampered), "")
	tampered = baseline.duplicate(true)
	tampered.first_draws.spawn_content[0] = "0"
	assert_eq(VECTOR.gameplay_mismatch(baseline, tampered), "first_draw_mismatch")
