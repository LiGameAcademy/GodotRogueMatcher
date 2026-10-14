extends GutTest

const ROW: SkillDefinition = preload("res://gameplay/progression/content/line_row_drop.tres")
const COLUMN: SkillDefinition = preload("res://gameplay/progression/content/line_column_drop.tres")

func _run(seed_value: int = 11) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	run.state.pending_rewards = 1
	run.state.rewards.consumed_count = 0
	run.enter_rewards()
	return run

func _offer(run: RunController, skill: SkillDefinition) -> SkillOffer:
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill, run.state.rewards.target_random)
	run.state.rewards.active_offer = offer
	run.enter_rewards()
	return offer

func test_row_drop_unlocks_places_and_allows_second_piece() -> void:
	var run: RunController = _run()
	var offer: SkillOffer = _offer(run, ROW)
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, ROW.skill_id)
	assert_true(result.success, result.error)
	assert_true(run.state.line_clear.row_unlocked)
	assert_false(run.state.line_clear.column_unlocked)
	assert_eq(result.created.size(), 1)
	assert_eq(result.created[0].content_id, LineClearState.CONTENT_ROW)
	var second: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(3, 3), 1)
	assert_not_null(second)
	assert_eq(second.content_id, LineClearState.CONTENT_ROW)
	var count: int = 0
	for piece: PieceState in run.state.rules.state.get_snapshot():
		if piece.content_id == LineClearState.CONTENT_ROW: count += 1
	assert_eq(count, 2)

func test_column_drop_is_independent_and_repeat_rejected() -> void:
	var run: RunController = _run(12)
	var first: SkillOffer = _offer(run, COLUMN)
	assert_true(SkillRules.apply(run, first.offer_id, COLUMN.skill_id).success)
	assert_true(run.state.line_clear.column_unlocked)
	run.state.pending_rewards = 1
	var again: SkillOffer = _offer(run, COLUMN)
	assert_false(SkillRules.apply(run, again.offer_id, COLUMN.skill_id).success)
	run.state.pending_rewards = 1
	var row_offer: SkillOffer = _offer(run, ROW)
	assert_true(SkillRules.apply(run, row_offer.offer_id, ROW.skill_id).success)
	assert_true(run.state.line_clear.row_unlocked)
	assert_true(run.state.line_clear.column_unlocked)

func test_catalog_includes_line_drops() -> void:
	assert_eq(SkillOfferGenerator.CATALOG.size(), 48)
	var ids: Array[StringName] = []
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		ids.append(skill.skill_id)
	assert_has(ids, &"line_row_drop")
	assert_has(ids, &"line_column_drop")
