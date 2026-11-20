extends GutTest

## Locks the author premise: one master seed per run; spawn/offer/effect streams derive from it.

func _run(seed_value: int = 42) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)

func test_live_consumers_share_one_master_derived_owner() -> void:
	var run: RunController = _run(42)
	assert_eq(RunSeedIdentity.error(run), "")
	assert_eq(run.state.random_streams.master_seed, 42)
	for id: StringName in RunRandomStreams.IDS:
		assert_eq(run.state.random_streams.stream(id).seed, RunRandomStreams.create(42, id).seed)

func test_recorder_header_seed_matches_master_and_rng_payload() -> void:
	var run: RunController = _run(1000)
	run.initialize("fixture_f6")
	var recorder: RunRecorder = RunRecorder.new()
	recorder.begin(run, "fixture", false)
	assert_eq(RunSeedIdentity.header_error(recorder.records[0], run), "")
	assert_eq(recorder.records[0].seed, "1000")
	assert_eq(recorder.records[0].rng.master_seed, "1000")

class FixedEntropy extends RefCounted:
	var value: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 77])
	func sample() -> PackedByteArray:
		return value

func test_natural_prepare_adopts_proposed_seed_as_sole_master() -> void:
	var entropy: FixedEntropy = FixedEntropy.new()
	var source: NewRunSeedSource = NewRunSeedSource.new()
	source.entropy_provider = entropy.sample
	var prepared: Dictionary = NewRunFactory.prepare(BoardRules.new(BoardState.new(9, 9), 5), null, source)
	assert_true(prepared.ok)
	var run: RunController = prepared.run
	assert_eq(run.state.random_streams.master_seed, 77)
	assert_eq(RunSeedIdentity.error(run), "")
	assert_eq(source.last_started(), -1)
	source.remember(run.state.random_streams.master_seed)
	assert_eq(source.last_started(), 77)

func test_bot_strategy_seed_does_not_become_a_second_gameplay_master() -> void:
	var run: RunController = _run(50)
	var before: Dictionary = run.state.random_streams.data()
	var strategy: RandomNumberGenerator = RandomNumberGenerator.new()
	strategy.seed = BotRunner.strategy_seed_for(50)
	for index: int in range(16):
		strategy.randi()
	assert_eq(run.state.random_streams.data(), before)
	assert_eq(RunSeedIdentity.error(run), "")
	assert_ne(BotRunner.strategy_seed_for(50), run.state.random_streams.master_seed)

func test_reset_counters_keeps_same_master_without_resampling() -> void:
	var run: RunController = _run(9)
	run.state.random_streams.stream(&"spawn_content").randi()
	run.state.random_streams.stream(&"offer_candidates").randi()
	run.state.reset_counters()
	assert_eq(run.state.random_streams.master_seed, 9)
	assert_eq(RunSeedIdentity.error(run), "")
	for id: StringName in RunRandomStreams.IDS:
		assert_eq(run.state.random_streams.stream(id).seed, RunRandomStreams.create(9, id).seed)
