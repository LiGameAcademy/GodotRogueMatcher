extends GutTest

## Independent .NET SHA256 vectors, ordered by protocol ID rather than construction order.
const VECTORS: Dictionary[int, Array] = {
	0: [2729845685990345877, 8752263775288148050, 8576717203482710280, 5422887974925471730, 6931660722589191756, 4233646529825458256],
	42: [2698757283641008609, 4156300916487032238, 8284178283302528712, 978293449253142013, 7461956290973307042, 7474628424099629659],
	9223372036854775807: [8075508656888403245, 1141245884172883644, 2131625620522659458, 8197513564564759495, 6038195424461096669, 4871028045272341391],
}

func _run(seed_value: int = 42) -> RunController:
	return RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)

func test_fixed_vectors_and_creation_order() -> void:
	assert_eq(BotRunner.strategy_seed_for(0), 100000)
	assert_eq(BotRunner.strategy_seed_for(9223372036854675807), 9223372036854775807)
	assert_eq(BotRunner.strategy_seed_for(9223372036854675808), 0)
	assert_eq(BotRunner.strategy_seed_for(9223372036854775807), 99999)
	assert_eq("sl-rng-v1\n42\nspawn_content\n".sha256_text(), "a573e9736a6ba1e1029ac75fa47d6d915d307dbe5c18900d92ef91db930dc86c")
	for seed_value: int in VECTORS:
		var streams: RunRandomStreams = RunRandomStreams.new(seed_value)
		for index: int in range(RunRandomStreams.IDS.size() - 1, -1, -1):
			var id: StringName = RunRandomStreams.IDS[index]
			assert_eq(streams.stream(id).seed, VECTORS[seed_value][index])
			assert_eq(RunRandomStreams.create(seed_value, id).state, streams.stream(id).state)
		# An unrelated entropy consumer cannot alter any of the six streams.
		var before: Dictionary = streams.data()
		var extra: RandomNumberGenerator = RandomNumberGenerator.new()
		extra.randomize()
		extra.randi()
		assert_eq(streams.data(), before)

func test_each_consumer_is_bound_to_its_named_stream_and_runs_are_independent() -> void:
	var run: RunController = _run()
	var other: RunController = _run()
	assert_same(run.state.random, run.state.random_streams.stream(&"spawn_position"))
	assert_same(run.state.spawning.content_random, run.state.random_streams.stream(&"spawn_content"))
	assert_same(run.state.rewards.candidate_random, run.state.random_streams.stream(&"offer_candidates"))
	assert_same(run.state.rewards.display_random, run.state.random_streams.stream(&"offer_order"))
	assert_same(run.state.rewards.target_random, run.state.random_streams.stream(&"offer_targets"))
	var initial: Dictionary = other.state.random_streams.data()
	for id: StringName in RunRandomStreams.IDS:
		var before: Dictionary = run.state.random_streams.data()
		run.state.random_streams.stream(id).randi()
		for untouched: StringName in RunRandomStreams.IDS:
			if untouched != id: assert_eq(run.state.random_streams.data().streams[String(untouched)], before.streams[String(untouched)])
	assert_eq(other.state.random_streams.data(), initial)
	run.state.reset_counters()
	assert_eq(run.state.random_streams.data(), initial)
	assert_same(run.state.random, run.state.random_streams.stream(&"spawn_position"))

func test_signed_64_bit_roundtrip_and_future_draws() -> void:
	var streams: RunRandomStreams = RunRandomStreams.new(9223372036854775807)
	var bounds: Array[int] = [0, 9223372036854775807, -9223372036854775807 - 1, -1]
	for bound: int in bounds:
		var encoded: Dictionary = streams.data()
		for id: StringName in RunRandomStreams.IDS:
			encoded.streams[String(id)] = {"seed": str(bound), "state": str(bound)}
		var decoded: RunRandomStreams = RunRandomStreams.from_data(JSON.parse_string(JSON.stringify(encoded)))
		assert_not_null(decoded)
		if decoded == null: continue
		assert_eq(decoded.data(), encoded)
		var copy: RunRandomStreams = RunRandomStreams.from_data(decoded.data())
		for id: StringName in RunRandomStreams.IDS:
			for index: int in range(8): assert_eq(decoded.stream(id).randi(), copy.stream(id).randi())

func test_invalid_protocol_or_missing_stream_is_rejected_without_touching_active_run() -> void:
	var streams: RunRandomStreams = RunRandomStreams.new(42)
	var before: Dictionary = streams.data()
	var bad: Dictionary = streams.data()
	bad.rng_scheme_version = "future"
	assert_null(RunRandomStreams.from_data(bad))
	bad = streams.data()
	bad.streams.erase("effect_execution")
	assert_null(RunRandomStreams.from_data(bad))
	for value: Variant in [42, -1, "-1", "01", "+1", "1\n", "9223372036854775808", "1e2"]:
		bad = streams.data()
		bad.master_seed = value
		assert_null(RunRandomStreams.from_data(bad))
		bad = streams.data()
		bad.streams.spawn_content.state = value
		if value is String and value == "-1": assert_not_null(RunRandomStreams.from_data(bad))
		else: assert_null(RunRandomStreams.from_data(bad))
	assert_eq(streams.data(), before)

func test_dynamic_execution_leaves_offer_streams_untouched() -> void:
	var run: RunController = _run()
	for index: int in range(6): run.state.rules.place_piece(Vector2i(index, 0), index % 2)
	var effect: ThinMaterialEffect = ThinMaterialEffect.new()
	var before: Dictionary = run.state.random_streams.data()
	var target: SkillTarget = effect.freeze_offer(SkillRules.effect_context(run.state), run.state.rewards.target_random)
	var error: String = AbilityEffectRunner.apply_skill_effect(run, effect, target, SkillApplyResult.new())
	assert_eq(error, "")
	for id: StringName in RunRandomStreams.IDS:
		var after: Dictionary = run.state.random_streams.data().streams[String(id)]
		if id == &"effect_execution": assert_ne(after, before.streams[String(id)])
		else: assert_eq(after, before.streams[String(id)])

func test_unique_position_and_color_do_not_draw_and_preview_is_read_only() -> void:
	var run: RunController = _run()
	for y: int in range(9):
		for x: int in range(9):
			if x != 8 or y != 8: run.state.rules.place_piece(Vector2i(x, y), (x + y) % 5)
	run.state.spawning.color_weights = [0, 0, 1, 0, 0]
	var before: Dictionary = run.state.random_streams.data()
	run.prepare_spawn_plan()
	assert_eq(run.state.random_streams.data(), before)
	run.state.spawning.preview(3)
	assert_eq(run.state.random_streams.data(), before)
	assert_not_null(run.spawn_one())
	assert_eq(run.state.random_streams.data(), before)

func test_replay_rejects_missing_protocol_and_stream_before_replacing_run() -> void:
	var run: RunController = _run()
	run.initialize()
	var recorder: RunRecorder = RunRecorder.new()
	recorder.begin(run, "fixture", false)
	var replay: RuleReplay = RuleReplay.new()
	assert_true(replay.restore_prefix(recorder.records), replay.error)
	var previous: RunController = replay.run
	var records: Array[Dictionary] = recorder.records.duplicate(true)
	records[0].erase("rng_scheme_version")
	assert_false(replay.restore_prefix(records))
	assert_eq(replay.error, "unsupported_rng_scheme")
	assert_same(replay.run, previous)
	for value: Variant in [null, 0, true, "unknown"]:
		records = recorder.records.duplicate(true)
		records[0].engine_build = value
		assert_false(replay.restore_prefix(records))
		assert_eq(replay.error, "engine_build_mismatch")
		assert_same(replay.run, previous)
	for value: Variant in [null, 0, true, "unverified-platform"]:
		records = recorder.records.duplicate(true)
		records[0].platform = value
		assert_false(replay.restore_prefix(records))
		assert_eq(replay.error, "platform_mismatch")
		assert_same(replay.run, previous)
	records = recorder.records.duplicate(true)
	records[0].rng.streams.erase("offer_targets")
	assert_false(replay.restore_prefix(records))
	assert_eq(replay.error, "invalid_random_streams")
	assert_same(replay.run, previous)
