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

static func x() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_x.tres") as SkillDefinition

static func x_catalog() -> Array[SkillDefinition]:
	return [l(), x(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func zs() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_zs.tres") as SkillDefinition

static func zs_catalog() -> Array[SkillDefinition]:
	return [l(), zs(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func u() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_u.tres") as SkillDefinition

static func u_catalog() -> Array[SkillDefinition]:
	return [l(), u(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func ring() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_ring.tres") as SkillDefinition

static func ring_catalog() -> Array[SkillDefinition]:
	return [u(), ring(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func square() -> SkillDefinition:
	return load("res://gameplay/skills/debug/shape_unlock/unlock_square.tres") as SkillDefinition

static func square_catalog() -> Array[SkillDefinition]:
	return [ring(), square(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func catalog() -> Array[SkillDefinition]:
	return [l(), t(), load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition]

static func populate(run: RunController, mode: String) -> void:
	if mode in RunController.SQUARE_INITIALIZATIONS:
		SquareTemplateDemo.populate(run, mode)
		return
	if mode in RunController.RING_INITIALIZATIONS:
		RingTemplateDemo.populate(run, mode)
		return
	if mode in RunController.U_INITIALIZATIONS:
		UTemplateDemo.populate(run, mode)
		return
	if mode in RunController.ZS_INITIALIZATIONS:
		ZsTemplateDemo.populate(run, mode)
		return
	var definition: SkillDefinition = t() if mode in ["fixture_shape_unlock_t", "fixture_shape_unlock_t_empty", "fixture_shape_unlock_t_two_rewards"] else l()
	if mode in RunController.PLUS_INITIALIZATIONS: definition = plus()
	if mode in RunController.X_INITIALIZATIONS: definition = x()
	var template: MatchShapeTemplate = (definition.choice_effect as UnlockShapeEffect).template
	for coordinate: Vector2i in template.offsets: run.state.rules.place_piece(coordinate, 0)
	if mode in ["fixture_shape_unlock", "fixture_shape_unlock_t", "fixture_shape_unlock_t_two_rewards", "fixture_shape_unlock_plus", "fixture_shape_unlock_plus_two_rewards", "fixture_shape_unlock_x", "fixture_shape_unlock_x_two_rewards"]: run.state.rules.place_piece(Vector2i(8, 8), 1)
	if mode == "fixture_shape_unlock_chain":
		run.abilities.assign_fuse(run.state.rules.state.get_piece_id(Vector2i(0, 2)))
		run.state.rules.place_piece(Vector2i(0, 3), 1)
		run.state.rules.place_piece(Vector2i(0, 4), 1)
	run.state.pending_rewards = 2 if mode in ["fixture_shape_unlock_t_two_rewards", "fixture_shape_unlock_plus_two_rewards", "fixture_shape_unlock_x_two_rewards"] else 1
