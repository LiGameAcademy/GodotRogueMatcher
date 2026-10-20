extends GutTest

func test_collision_uses_a_different_seed_without_retrying() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 161
	var source: RunSeedSource = RunSeedSource.new(random)
	var before: int = random.state
	var first: int = source.next_seed()
	var after: int = random.state
	random.state = before
	var second: int = source.next_seed()
	assert_ne(second, first)
	assert_eq(second, (first + 1) & 0xFFFFFFFF)
	assert_eq(random.state, after, "collision consumes exactly one sample")

func test_new_seeds_do_not_consume_existing_run_streams() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 161)
	run.initialize()
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var source: RunSeedSource = RunSeedSource.new()
	var first: int = source.next_seed()
	assert_ne(source.next_seed(), first)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)

func test_explicit_seed_still_reproduces_initial_board_and_streams() -> void:
	var first: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 161)
	var second: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 161)
	first.initialize()
	second.initialize()
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(first)), RunSnapshot.digest(RunSnapshot.capture(second)))
