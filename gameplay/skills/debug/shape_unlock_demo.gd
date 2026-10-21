class_name ShapeUnlockDemo
extends RefCounted

## Explicit acceptance recipes, never added to the production SkillOfferGenerator.CATALOG.
const PROFILE: StringName = &"shape-unlock-fixture-v1"
# Load recipes only after Autoload setup; preloading SkillDefinition here creates a class cycle.
static func l() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_l.tres") as SkillDefinition

static func t() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_t.tres") as SkillDefinition

static func catalog() -> Array[SkillDefinition]:
	return [l(), t(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func populate(run: RunController, mode: String) -> void:
	var template: MatchShapeTemplate = (l().choice_effect as UnlockShapeEffect).template
	for coordinate: Vector2i in template.offsets: run.state.rules.place_piece(coordinate, 0)
	if mode == "fixture_shape_unlock": run.state.rules.place_piece(Vector2i(8, 8), 1)
	if mode == "fixture_shape_unlock_chain":
		run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i(0, 2)))
		run.state.rules.place_piece(Vector2i(0, 3), 1)
		run.state.rules.place_piece(Vector2i(0, 4), 1)
	run.state.pending_rewards = 1
