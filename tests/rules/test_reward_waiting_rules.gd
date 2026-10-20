extends GutTest

const CORE: SkillDefinition = preload("res://gameplay/progression/content/core_drop.tres")
const SCORE: SkillDefinition = preload("res://gameplay/progression/content/score_multiplier.tres")

class FailedFreeze extends ChoiceEffect:
	func rejection(_context: ChoiceEffectContext) -> String:
		return ""
	func freeze(_context: ChoiceEffectContext, random: RandomNumberGenerator) -> SkillTarget:
		random.randi()
		return SkillTarget.new()
	func build(_context: ChoiceEffectContext, _target: SkillTarget) -> ChoiceEffectRequest:
		var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
		request.error = "injected_freeze_failure"
		return request

func _run() -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 133)
	run.state.pending_rewards = 1
	run.enter_rewards()
	return run

func _offer(run: RunController, choices: Array[SkillDefinition]) -> SkillOffer:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices.assign(choices)
	for skill: SkillDefinition in choices: offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	run.state.rewards.next_offer_id += 1
	return offer

func test_partial_invalid_offer_keeps_identity_targets_and_random_without_replacement() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run, [CORE, SCORE])
	run.state.rules.place_piece(offer.targets[CORE.skill_id].coordinate, 0)
	var before: int = run.state.rewards.candidate_random.state
	var target_before: int = run.state.rewards.target_random.state
	assert_same(run.prepare_offer(), offer)
	assert_true(offer.unavailable.has(CORE.skill_id))
	assert_false(offer.unavailable.has(SCORE.skill_id))
	assert_eq(run.state.rewards.candidate_random.state, before)
	assert_eq(run.state.rewards.target_random.state, target_before)
	assert_eq(run.state.pending_rewards, 1)

func test_all_invalid_offer_rebuilds_same_reward_once_without_consuming_it() -> void:
	var run: RunController = _run()
	var old: SkillOffer = _offer(run, [CORE])
	run.state.rules.place_piece(old.targets[CORE.skill_id].coordinate, 0)
	var next: SkillOffer = run.prepare_offer()
	assert_not_null(next)
	if next == null: return
	assert_ne(next.offer_id, old.offer_id)
	assert_eq(next.reward_id, old.reward_id)
	assert_eq(next.replaces_offer_id, old.offer_id)
	assert_eq(run.state.pending_rewards, 1)
	assert_eq(run.state.rewards.consumed_count, 0)
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, run.state.action_id)
	command.reward_id = old.reward_id
	command.offer_id = old.offer_id
	command.skill_id = CORE.skill_id
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_false(run.execute_command(command).accepted)
	assert_eq(run.state.rewards.consumed_count, 0)
	assert_same(run.state.rewards.active_offer, next)
	assert_ne(before, "")

func test_nested_popup_snapshot_isolates_every_target_collection() -> void:
	var original: CompositeSkillTarget = CompositeSkillTarget.new()
	var leaf: SkillTarget = SkillTarget.new()
	leaf.piece_ids = [1, 2]
	leaf.color_groups.append(PackedInt64Array([1, 2]))
	original.leaf_targets.append(leaf)
	var copy: CompositeSkillTarget = original.copy() as CompositeSkillTarget
	copy.leaf_targets[0].piece_ids.clear()
	copy.leaf_targets[0].color_groups[0].clear()
	assert_eq(leaf.piece_ids, [1, 2])
	assert_eq(leaf.color_groups[0], PackedInt64Array([1, 2]))

func test_second_complete_invalidation_stops_without_new_offer_or_repair() -> void:
	var run: RunController = _run()
	var original: SkillOffer = _offer(run, [CORE])
	run.state.rules.place_piece(original.targets[CORE.skill_id].coordinate, 0)
	var replacement: SkillOffer = run.prepare_offer()
	assert_true(run.state.rewards.repair_used)
	replacement.choices = [CORE]
	replacement.targets[CORE.skill_id] = SkillRules.freeze_target(run.state, CORE)
	run.state.rules.place_piece(replacement.targets[CORE.skill_id].coordinate, 1)
	var next_id: int = run.state.rewards.next_offer_id
	var random_before: Dictionary = RunSnapshot.random_data(run.state.rewards.candidate_random)
	assert_null(run.prepare_offer())
	assert_eq(run.state.rule_error, "reward_repair_already_used")
	assert_same(run.state.rewards.active_offer, replacement)
	assert_eq(run.state.rewards.next_offer_id, next_id)
	assert_eq(RunSnapshot.random_data(run.state.rewards.candidate_random), random_before)
	assert_eq(run.state.pending_rewards, 1)

func test_failed_freeze_keeps_all_formal_streams_identity_and_reward() -> void:
	var run: RunController = _run()
	var broken: SkillDefinition = CORE.duplicate() as SkillDefinition
	broken.levels = []
	broken.maximum_level = 0
	broken.choice_effect = FailedFreeze.new()
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([broken, SCORE])
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_null(generator.generate(run))
	assert_eq(generator.last_error, "injected_freeze_failure")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_false(run.state.rewards.repair_used)
	assert_eq(run.state.rewards.next_offer_id, 1)

func test_one_and_two_card_groups_are_complete_but_zero_pool_is_an_error() -> void:
	for size: int in [1, 2]:
		var run: RunController = _run()
		var pool: Array[SkillDefinition] = [SCORE]
		if size == 2: pool.append(CORE)
		var generator: SkillOfferGenerator = SkillOfferGenerator.new()
		generator.set_catalog(pool)
		var offer: SkillOffer = run.prepare_offer(true, generator)
		assert_not_null(offer)
		if offer == null: continue
		assert_eq(offer.choices.size(), size)
		assert_eq(run.state.rewards.consumed_count, 0)
		assert_eq(run.state.pending_rewards, 1)
	var empty: RunController = _run()
	var before: Dictionary = RunSnapshot.random_data(empty.state.rewards.candidate_random)
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	generator.set_catalog([])
	assert_null(empty.prepare_offer(true, generator))
	assert_eq(empty.state.rule_error, "no_legal_candidates")
	assert_eq(empty.state.pending_rewards, 1)
	assert_eq(empty.state.rewards.next_offer_id, 1)
	assert_eq(RunSnapshot.random_data(empty.state.rewards.candidate_random), before)

func test_successful_choose_duplicate_keeps_result_and_consumes_once() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run, [SCORE])
	var command: ChooseSkillCommand = ChooseSkillCommand.new(run.state.run_id, 1, run.state.action_id)
	command.offer_id = offer.offer_id
	command.reward_id = offer.reward_id
	command.skill_id = SCORE.skill_id
	var result: CommandResult = run.execute_command(command)
	assert_true(result.accepted)
	var after: String = RunSnapshot.digest(RunSnapshot.capture(run))
	assert_same(run.execute_command(command), result)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), after)
	assert_eq(run.state.rewards.consumed_count, 1)
	assert_eq(run.state.pending_rewards, 0)
	assert_eq(SkillRules.level(run.state, SCORE), 1)
