extends GutTest

var previous_run: RunController

func before_each() -> void:
	previous_run = GameManager.run
	GameManager.reset_game(RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7))

func after_each() -> void:
	GameManager.reset_game(previous_run)

func test_one_thousand_points_grants_four_rewards_and_progress_uses_actual_interval() -> void:
	LevelUpSystem.reset_system()
	assert_true(LevelUpSystem.check_level_up(1000))
	assert_eq(LevelUpSystem.pending_rewards, 4)
	assert_eq(LevelUpSystem.next_milestone, 1500)
	assert_almost_eq(LevelUpSystem.get_level_progress(1000), 1.0 / 6.0, 0.0001)
	assert_false(LevelUpSystem.check_level_up(1000))
	assert_eq(LevelUpSystem.pending_rewards, 4)
	LevelUpSystem.reset_system()
	assert_eq(LevelUpSystem.get_level_progress(0), 0.0)

func test_milestones_are_strictly_increasing_including_tail() -> void:
	var previous: int = 0
	for index: int in range(20):
		var threshold: int = LevelUpSystem.CONFIG.threshold(index)
		assert_gt(threshold, previous)
		previous = threshold

func test_thinning_freezes_targets_and_never_removes_fuse_or_partner_or_scores() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.enter_rewards()
	run.state.pending_rewards = 1
	run.state.rewards.consumed_count = 2
	var core: PieceState = run.abilities.add_core(Vector2i.ZERO)
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(1, 0), 1)
	run.abilities.assign_fuse(fuse.piece_id)
	for x: int in range(2, 6): run.state.rules.place_piece(Vector2i(x, 0), x % 5)
	var definition: SkillDefinition = preload("res://gameplay/progression/content/instant_thin.tres")
	var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
	offer.choices[0] = definition
	var targets: SkillTarget = SkillTarget.new()
	var ids: Array[int] = SkillRules.unmarked_material(run.state)
	for index: int in range(3): targets.piece_ids.append(ids[index])
	offer.targets[definition.skill_id] = targets
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, definition.skill_id)
	assert_true(result.success)
	assert_eq(result.removed.size(), 3)
	assert_eq(run.state.rules.state.get_piece_count(), 3)
	assert_not_null(run.state.rules.state.get_piece(core.piece_id))
	assert_not_null(run.state.rules.state.get_piece(fuse.piece_id))
	assert_eq(run.state.ledger.total, 0)
	assert_eq(result.matches.size(), 0)
	assert_eq(run.state.pending_rewards, 0)
	assert_false(SkillOfferGenerator.build_profile(run.state).has(&"thin"))
	assert_false(SkillRules.apply(run, offer.offer_id, definition.skill_id).success)

func test_thinning_invalid_target_preserves_whole_action() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 7)
	run.enter_rewards()
	run.state.pending_rewards = 1
	run.state.rewards.consumed_count = 2
	var piece: PieceState = run.state.rules.place_piece(Vector2i.ZERO, 0)
	var offer: SkillOffer = SkillOfferGenerator.new().generate(run)
	var skill: SkillDefinition = preload("res://gameplay/progression/content/instant_thin.tres")
	offer.choices[0] = skill
	var target: SkillTarget = SkillTarget.new()
	target.piece_ids = [piece.piece_id, piece.piece_id]
	offer.targets[skill.skill_id] = target
	assert_false(SkillRules.apply(run, offer.offer_id, skill.skill_id).success)
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.rules.state.get_piece_count(), 1)
	assert_eq(run.state.action_id, 0)

func test_midgame_pool_includes_new_utility_and_freezes_real_targets() -> void:
	var found: int = 0
	for seed_value: int in range(100):
		var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
		run.state.pending_rewards = 1
		run.state.rewards.consumed_count = 2
		for x: int in range(4): run.state.rules.place_piece(Vector2i(x, 0), x)
		var generator: SkillOfferGenerator = SkillOfferGenerator.new()
		var board_random: int = run.state.random.state
		var offer: SkillOffer = generator.generate(run)
		for skill: SkillDefinition in offer.choices:
			if skill.skill_id == &"instant_thin":
				found += 1
				assert_eq(offer.targets[skill.skill_id].piece_ids.size(), 3)
				assert_same(generator.generate(run), offer)
		assert_eq(run.state.random.state, board_random)
	assert_gt(found, 0)
