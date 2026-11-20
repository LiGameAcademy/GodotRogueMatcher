class_name MixedTemplateDemo
extends RefCounted

## Fixed technical probes; these pairs are not the #119 human screening selection.
const CASES: Array[String] = ["lt", "plus_x", "independent", "nested"]
const SHAPES: Array[String] = ["l", "t", "plus", "x", "zs", "u", "ring", "square"]
const MODES: Array[String] = ["fixture_mixed_lt", "fixture_mixed_lt_baseline", "fixture_mixed_plus_x", "fixture_mixed_plus_x_baseline", "fixture_mixed_independent", "fixture_mixed_independent_baseline", "fixture_mixed_nested", "fixture_mixed_nested_baseline"]

static func templates(mode: String) -> Array[MatchShapeTemplate]:
	var result: Array[MatchShapeTemplate] = []
	if mode.ends_with("_baseline"): return result
	var ids: Array[String] = ["plus", "x"]
	if case_id(mode) == "nested": ids = SHAPES
	elif case_id(mode) == "lt": ids = ["l", "t"]
	for id: String in ids:
		result.append(load("res://gameplay/board/matching/%s_template.tres" % id) as MatchShapeTemplate)
	return result

static func case_id(mode: String) -> String:
	return mode.trim_prefix("fixture_mixed_").trim_suffix("_baseline")

static func new_run(mode: String) -> RunController:
	assert(mode in MODES)
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates(mode)), 119, null, RunController.MIXED_PROFILE)
	run.initialize(mode)
	return run

static func target(mode: String) -> Vector2i:
	if case_id(mode) == "nested": return Vector2i(4, 2)
	if case_id(mode) == "independent": return Vector2i(1, 2)
	return Vector2i(2, 2)

static func source(mode: String) -> Vector2i:
	return target(mode) + Vector2i.DOWN

static func cells(mode: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	match case_id(mode):
		"lt": result.assign([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 3), Vector2i(1, 4)])
		"plus_x", "nested":
			for y: int in range(3):
				for x: int in range(3): result.append(Vector2i(x, y))
			if case_id(mode) == "nested": result.append_array([Vector2i(3, 2), Vector2i(4, 2)])
		"independent": result.assign([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(5, 0), Vector2i(7, 0), Vector2i(6, 1), Vector2i(5, 2), Vector2i(7, 2)])
	return result

static func populate(run: RunController, mode: String) -> void:
	for cell: Vector2i in cells(mode):
		if cell != target(mode): run.state.rules.place_piece(cell, 0)
	run.state.rules.place_piece(source(mode), 0)
	run.state.rules.place_piece(Vector2i(8, 8), 1)

## Preserve the production effect/parameters; only this fixture admits it at reward one.
static func catalog() -> Array[SkillDefinition]:
	var original: SkillDefinition = load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition
	var choice: SkillDefinition = original.duplicate(true) as SkillDefinition
	choice.skill_id = &"fixture_mixed_refill"
	choice.title = "测试：留白一手"
	choice.minimum_reward = 1
	return [choice]
