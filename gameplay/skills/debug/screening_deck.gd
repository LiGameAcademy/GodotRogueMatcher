class_name ScreeningDeck
extends RefCounted

const CONFIGS: Array[String] = ["baseline", "l", "t", "plus", "x", "zs"]
const TASKS: Array[String] = ["free", "direct", "wrong", "overlap", "outside"]

static func config(key: String) -> ScreeningConfig:
	assert(key in CONFIGS)
	return load("res://tools/screening_playground/configs/%s.tres" % key) as ScreeningConfig

static func modes() -> Array[String]:
	var result: Array[String] = []
	for key: String in CONFIGS:
		for task: String in TASKS.slice(1): result.append("screening_%s_%s" % [key, task])
	return result

static func key_of(mode: String) -> String:
	return mode.trim_prefix("screening_").get_slice("_", 0)

static func task_of(mode: String) -> String:
	return mode.get_slice("_", 2)

static func new_run(key: String, task: String) -> RunController:
	assert(key in CONFIGS and task in TASKS)
	var settings: ScreeningConfig = config(key)
	var templates: Array[MatchShapeTemplate] = []
	if settings.template != null: templates.append(settings.template)
	var profile: StringName = RunController.SCREENING_PROFILE if task == "free" else RunController.SCREENING_FIXED_PROFILE
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5, templates), settings.seed_value, null, profile)
	run.initialize("normal" if task == "free" else "screening_%s_%s" % [key, task])
	return run

static func footprint(key: String) -> Array[Vector2i]:
	var settings: ScreeningConfig = config(key)
	if settings.template != null: return settings.template.offsets.duplicate()
	var result: Array[Vector2i] = []
	for x: int in range(5): result.append(Vector2i(x, 2))
	return result

static func target(mode: String) -> Vector2i:
	return footprint(key_of(mode)).back()

static func source(mode: String) -> Vector2i:
	return target(mode) + Vector2i.DOWN

static func populate(run: RunController, mode: String) -> void:
	var key: String = key_of(mode)
	var task: String = task_of(mode)
	var cells: Array[Vector2i] = footprint(key)
	if task == "overlap":
		for x: int in range(5):
			var cell: Vector2i = Vector2i(x, 2)
			if not cells.has(cell): cells.append(cell)
	for cell: Vector2i in cells:
		if cell != target(mode): run.state.rules.place_piece(cell, 1 if task == "wrong" and cell == cells[0] else 0)
	run.state.rules.place_piece(source(mode), 0)
	if task == "outside": run.state.rules.place_piece(Vector2i(8, 0), 0)
	run.state.rules.place_piece(Vector2i(8, 8), 1)

## Fixed tasks isolate prediction; free play uses the untouched production pool.
static func fixed_catalog() -> Array[SkillDefinition]:
	var original: SkillDefinition = load("res://gameplay/progression/content/refill_less.tres") as SkillDefinition
	var choice: SkillDefinition = original.duplicate(true) as SkillDefinition
	choice.skill_id = &"fixture_screening_refill"
	choice.title = "定向题：留白一手"
	choice.minimum_reward = 1
	return [choice]
