extends GutTest

class Entropy extends RefCounted:
	var calls: int = 0
	var value: Variant = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 42])
	func sample() -> Variant:
		calls += 1
		return value

func test_prepare_is_not_commit_and_collision_has_one_bounded_correction() -> void:
	var entropy: Entropy = Entropy.new()
	var source: NewRunSeedSource = NewRunSeedSource.new()
	source.entropy_provider = entropy.sample
	assert_eq(source.propose().seed, 42)
	assert_eq(source.last_started(), -1)
	source.remember(42)
	assert_eq(source.propose().seed, 43)
	assert_eq(source.propose().seed, 43)
	assert_eq(source.last_started(), 42)
	assert_eq(entropy.calls, 3)
	source.remember(43)
	assert_eq(source.propose().seed, 42, "only the last actual seed is excluded, not all history")

func test_sign_bit_mask_maximum_wrap_zero_and_saved_metadata_boundary() -> void:
	var entropy: Entropy = Entropy.new()
	var source: NewRunSeedSource = NewRunSeedSource.new()
	source.entropy_provider = entropy.sample
	assert_eq(source.propose(42).seed, 43)
	source.remember(7)
	assert_eq(source.propose(42).seed, 42, "actual in-process run wins over stale metadata")
	entropy.value = PackedByteArray([255, 255, 255, 255, 255, 255, 255, 255])
	assert_eq(source.propose().seed, NewRunSeedSource.MAX_SEED)
	source.remember(NewRunSeedSource.MAX_SEED)
	assert_eq(source.propose().seed, 0)
	entropy.value = PackedByteArray([128, 0, 0, 0, 0, 0, 0, 0])
	assert_eq(source.propose().seed, 0)

func test_entropy_failure_has_no_fallback_or_identity_commit() -> void:
	var entropy: Entropy = Entropy.new()
	var source: NewRunSeedSource = NewRunSeedSource.new()
	source.entropy_provider = entropy.sample
	source.remember(42)
	for value: Variant in [null, "bytes", PackedByteArray(), PackedByteArray([1, 2]), 123]:
		entropy.value = value
		var result: Dictionary = source.propose()
		assert_false(result.ok)
		assert_eq(result.reason, "new_run_entropy_failed")
		assert_false(result.has("seed"))
		assert_eq(source.last_started(), 42)
	assert_eq(entropy.calls, 5)

func test_explicit_development_seed_is_not_sampled_or_corrected() -> void:
	var entropy: Entropy = Entropy.new()
	var source: NewRunSeedSource = NewRunSeedSource.new()
	source.entropy_provider = entropy.sample
	source.remember(42)
	var rules: BoardRules = BoardRules.new(BoardState.new(9, 9), 5)
	var fixed: RunController = RunController.new(rules, 42)
	var prepared: Dictionary = NewRunFactory.prepare(rules, null, source, fixed)
	assert_true(prepared.ok)
	assert_same(prepared.run, fixed)
	assert_eq(fixed.state.random_streams.master_seed, 42)
	assert_eq(entropy.calls, 0)

func test_preparation_failure_does_not_commit_or_touch_another_run_streams() -> void:
	var entropy: Entropy = Entropy.new()
	var source: NewRunSeedSource = NewRunSeedSource.new()
	source.entropy_provider = entropy.sample
	source.remember(23)
	var old: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 23)
	var before: Dictionary = old.state.random_streams.data()
	var invalid: StageConfig = preload("res://gameplay/progression/stages/stage_config.tres").duplicate(true) as StageConfig
	invalid.targets = [1]
	var result: Dictionary = NewRunFactory.prepare(BoardRules.new(BoardState.new(9, 9), 5), invalid, source)
	assert_false(result.ok)
	assert_eq(source.last_started(), 23)
	assert_eq(old.state.random_streams.data(), before)

func test_native_entropy_bytes_are_in_range_without_using_gameplay_or_global_rng() -> void:
	var source: NewRunSeedSource = NewRunSeedSource.new()
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 42)
	var before: Dictionary = run.state.random_streams.data()
	seed(123)
	var expected: int = randi()
	seed(123)
	var sampled: Dictionary = source.propose()
	assert_true(sampled.ok)
	assert_gte(int(sampled.get("seed", -1)), 0)
	assert_eq(randi(), expected)
	assert_eq(run.state.random_streams.data(), before)
