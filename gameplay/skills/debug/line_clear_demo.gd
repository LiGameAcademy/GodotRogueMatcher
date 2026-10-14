class_name LineClearDemo
extends RefCounted

## Deterministic teaching/test fixture, never a balance sample. Acquisition uses the shipped runner.
static func populate(run: RunController, wide: bool = false) -> void:
	run.state.line_clear.row_unlocked = true
	run.state.line_clear.column_unlocked = true
	if wide:
		run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(0, 3), 0)
		run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(6, 6), 2)
		for y: int in [2, 3, 4]: run.state.rules.place_piece(Vector2i(1, y), y)
		for x: int in [5, 6, 7]: run.state.rules.place_piece(Vector2i(x, 5), x % 5)
	else:
		run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(0, 0), 0)
		run.abilities.add_line_piece(LineClearState.AXIS_COLUMN, Vector2i(4, 4), 2)
		for x: int in [1, 2]: run.state.rules.place_piece(Vector2i(x, 0), x)
		for y: int in [1, 2]: run.state.rules.place_piece(Vector2i(4, y), y)
	_install(run, preload("res://gameplay/progression/content/line_manual_clear.tres"))
	if wide:
		_install(run, preload("res://gameplay/progression/content/line_row_span.tres"))
		_install(run, preload("res://gameplay/progression/content/line_column_span.tres"))

static func _install(run: RunController, skill: SkillDefinition) -> void:
	run.state.pending_rewards = 1
	run.enter_rewards()
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = run.state.rewards.consumed_count + 1
	offer.choices = [skill]
	offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
	var result: SkillApplyResult = SkillRules.apply(run, offer.offer_id, skill.skill_id)
	if not result.success: run.report_error(result.error)
