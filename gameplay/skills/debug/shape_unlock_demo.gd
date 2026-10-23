class_name ShapeUnlockDemo
extends RefCounted

## Explicit acceptance recipes, never added to the production SkillOfferGenerator.CATALOG.
const PROFILE: StringName = &"shape-unlock-fixture-v1"
# Load recipes only after Autoload setup; preloading SkillDefinition here creates a class cycle.
static func l() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_l.tres") as SkillDefinition

static func t() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_t.tres") as SkillDefinition

static func plus() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_plus.tres") as SkillDefinition

static func plus_catalog() -> Array[SkillDefinition]:
	return [l(), plus(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func catalog() -> Array[SkillDefinition]:
	return [l(), t(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func populate(run: RunController, mode: String) -> void:
	var definition: SkillDefinition = t() if mode in ["fixture_shape_unlock_t", "fixture_shape_unlock_t_empty", "fixture_shape_unlock_t_two_rewards"] else l()
	if mode in RunController.PLUS_INITIALIZATIONS: definition = plus()
	var template: MatchShapeTemplate = (definition.choice_effect as UnlockShapeEffect).template
	for coordinate: Vector2i in template.offsets: run.state.rules.place_piece(coordinate, 0)
	if mode in ["fixture_shape_unlock", "fixture_shape_unlock_t", "fixture_shape_unlock_t_two_rewards", "fixture_shape_unlock_plus", "fixture_shape_unlock_plus_two_rewards"]: run.state.rules.place_piece(Vector2i(8, 8), 1)
	if mode == "fixture_shape_unlock_chain":
		run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i(0, 2)))
		run.state.rules.place_piece(Vector2i(0, 3), 1)
		run.state.rules.place_piece(Vector2i(0, 4), 1)
	run.state.pending_rewards = 2 if mode in ["fixture_shape_unlock_t_two_rewards", "fixture_shape_unlock_plus_two_rewards"] else 1
