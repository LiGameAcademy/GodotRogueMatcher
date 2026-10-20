class_name TransformationDemo
extends RefCounted

## Fixed conversion offer for author review and exact command replay, not a balance sample.
static func populate(run: RunController) -> void:
	for index: int in range(12):
		run.state.rules.place_piece(Vector2i(index % 6 + 1, index / 6 * 3 + 2), index % 5)
	var fuse: PieceState = run.state.rules.place_piece(Vector2i(7, 6), 4)
	run.abilities.assign_fuse(fuse.piece_id)
	run.abilities.add_core(Vector2i(7, 7), 2)
	run.state.pending_rewards = 1
	run.state.rewards.consumed_count = 2
	var offer: SkillOffer = SkillOffer.new()
	offer.offer_id = run.state.rewards.next_offer_id
	run.state.rewards.next_offer_id += 1
	offer.reward_id = 3
	for skill: SkillDefinition in [preload("res://gameplay/progression/content/instant_core_transform.tres"), preload("res://gameplay/progression/content/instant_row_transform.tres"), preload("res://gameplay/progression/content/instant_column_transform.tres")]:
		offer.choices.append(skill)
		offer.targets[skill.skill_id] = SkillRules.freeze_target(run.state, skill)
	run.state.rewards.active_offer = offer
