extends RefCounted

## Acceptance-only nested recipe; ordinary dynamic selectors and offer generation remain unchanged.
# Load the Resource after Autoload setup, avoiding the existing SkillDefinition/RunController load cycle.
# Keep the fixture catalog local while exercising the normal offer revalidation/command gate.
## sl-rng-v1 fixture seed; legacy v43 seed 145 and its captures remain historical evidence.
const SEED: int = 13

class RecipeRun extends RunController:
	func offer_catalog() -> Array[SkillDefinition]:
		return [load("res://tools/chain_rhythm_acceptance/composite_rhythm.tres") as SkillDefinition]

static func create(seed_value: int = SEED) -> RunController:
	var run: RunController = RecipeRun.new(BoardRules.new(BoardState.new(9, 9), 5), seed_value)
	for x: int in range(1, 5): run.state.rules.place_piece(Vector2i(x, 2), 0)
	run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i(3, 2)))
	for at: Vector2i in [Vector2i(5, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(8, 8)]:
		run.state.rules.place_piece(at, 1)
	run.abilities.upgrade_reward()
	run.state.pending_rewards = 1
	run.enter_rewards()
	var generator: SkillOfferGenerator = SkillOfferGenerator.new()
	var skill: SkillDefinition = load("res://tools/chain_rhythm_acceptance/composite_rhythm.tres") as SkillDefinition
	generator.set_catalog([skill])
	if generator.generate(run) == null: push_error(generator.last_error + ": " + SkillRules.rejection(run.state, skill, run.abilities.config))
	return run
