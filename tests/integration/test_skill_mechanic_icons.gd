extends GutTest

const CARD: PackedScene = preload("res://ui/skill_card.tscn")
const BUILD: PackedScene = preload("res://ui/build_card/build_card.tscn")
const BUILD_SCRIPT: Script = preload("res://ui/build_card/build_card.gd")
var old_locale: String

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	old_locale = TranslationServer.get_locale()

func after_each() -> void:
	TranslationServer.set_locale(old_locale)
	await wait_process_frames(2)

func test_registered_icons_match_choices_catalog_and_compact_build_without_mutating_run() -> void:
	var run: RunController = AestheticCases.create("cards")
	var config: String = RunSnapshot.digest(RunSnapshot.config(run))
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for preset: GameTheme in GameThemes.ALL:
			for id: StringName in SkillMechanicIcons.TEXTURES:
				var skill: SkillDefinition = load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition
				var card: SkillCard = CARD.instantiate() as SkillCard
				var build: BUILD_SCRIPT = BUILD.instantiate() as BUILD_SCRIPT
				add_child(card)
				add_child(build)
				var frozen: SkillTarget = SkillRules.freeze_target(run.state, skill)
				var displayed: String = RunSnapshot.digest(RunSnapshot.capture(run))
				card.configure(skill, frozen)
				build.configure(skill, 1, 2)
				GameThemeUi.apply(card, preset)
				GameThemeUi.apply(build, preset)
				await wait_process_frames(3)
				assert_true(card.mechanic_icon.visible)
				assert_true(build.mechanic_icon.visible)
				assert_false(build.symbol.visible)
				assert_same(card.mechanic_icon.texture, build.mechanic_icon.texture)
				assert_eq(card.mechanic_icon.rotation_degrees, SkillMechanicIcons.rotation_for(id))
				assert_eq(build.mechanic_icon.rotation_degrees, card.mechanic_icon.rotation_degrees)
				assert_true(build.mechanic_role.visible)
				assert_eq(build.mechanic_role.text, SkillMechanicIcons.role_for(id))
				assert_string_contains(build.tooltip_text, tr(skill.title))
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), displayed)
				card.configure_catalog(skill, run)
				await wait_process_frames(3)
				assert_eq(card.mechanic_icon.rotation_degrees, SkillMechanicIcons.rotation_for(id))
				assert_same(card.mechanic_icon.texture, build.mechanic_icon.texture)
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), displayed)
				card.queue_free()
				build.queue_free()
				await wait_process_frames(1)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config)

func test_unregistered_and_same_tag_cards_keep_fallback_and_reused_nodes_clear_previous_icons() -> void:
	var card: SkillCard = CARD.instantiate() as SkillCard
	var build: BUILD_SCRIPT = BUILD.instantiate() as BUILD_SCRIPT
	add_child_autofree(card)
	add_child_autofree(build)
	var column: SkillDefinition = load("res://gameplay/progression/content/line_column_drop.tres") as SkillDefinition
	var core: SkillDefinition = load("res://gameplay/progression/content/core_drop.tres") as SkillDefinition
	var unknown: SkillDefinition = core.duplicate() as SkillDefinition
	unknown.skill_id = &"unregistered_same_tags"
	for skill: SkillDefinition in [column, core, unknown]:
		card.configure(skill, SkillTarget.new())
		build.configure(skill, 1, 0)
		if skill == unknown:
			assert_null(card.mechanic_icon.texture)
			assert_false(card.mechanic_icon.visible)
			assert_false(build.mechanic_icon.visible)
			assert_true(build.symbol.visible)
			assert_false(build.symbol.text.is_empty())
			assert_false(build.mechanic_role.visible)
		else:
			assert_true(build.mechanic_icon.visible)
			assert_eq(card.mechanic_icon.rotation_degrees, 90.0 if skill == column else 0.0)
	assert_eq(core.skill_id, &"core_drop")

func test_orientation_and_modulation_are_instance_local_and_do_not_intercept_input() -> void:
	var a: SkillCard = CARD.instantiate() as SkillCard
	var b: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(a)
	add_child_autofree(b)
	var row: SkillDefinition = load("res://gameplay/progression/content/line_row_drop.tres") as SkillDefinition
	var column: SkillDefinition = load("res://gameplay/progression/content/line_column_drop.tres") as SkillDefinition
	a.configure(row, SkillTarget.new())
	b.configure(column, SkillTarget.new())
	await wait_process_frames(3)
	assert_same(a.mechanic_icon.texture, b.mechanic_icon.texture)
	a.mechanic_icon.modulate = Color.RED
	assert_eq(b.mechanic_icon.modulate, Color.WHITE)
	assert_eq(b.mechanic_icon.rotation_degrees, 90.0)
	assert_eq(a.mechanic_icon.rotation_degrees, 0.0)
	assert_eq(a.mechanic_icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(b.mechanic_icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
