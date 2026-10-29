extends GutTest
## Definition, owned state and real offer projections share the same generator.

const POOL: PackedScene = preload("res://ui/skill_pool/skill_pool.tscn")
const CARD: PackedScene = preload("res://ui/skill_card.tscn")
var _locale: String
var _run: RunController
var _size: Vector2i
var _scale: Vector2i

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_locale = TranslationServer.get_locale()
	_size = get_window().size
	_scale = get_window().content_scale_size
	TranslationServer.set_locale("en_US")
	_run = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	_run.initialize("fixture_dye")
	assert_eq(_run.state.rule_error, "")

func after_each() -> void:
	get_tree().paused = false
	TranslationServer.set_locale(_locale)
	get_window().size = _size
	get_window().content_scale_size = _scale
	_run.retire()
	await wait_process_frames(2)

func _skill(id: String) -> SkillDefinition:
	return load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition

func test_definition_owned_proposed_max_and_expired_contexts_do_not_fabricate_offers() -> void:
	var multiplier: SkillDefinition = _skill("score_multiplier")
	assert_string_contains(SkillPoolText.rule_view(_run, multiplier).context, "Definition only")
	_run.state.explosion.multiplier_level = 2
	assert_string_contains(SkillPoolText.rule_view(_run, multiplier).text, "0.4")
	assert_string_contains(SkillPoolText.rule_view(_run, multiplier).context, "Lv.2")
	var target: SkillTarget = SkillRules.freeze_target(_run.state, multiplier)
	assert_eq(target.level_after, 3)
	var card: SkillCard = CARD.instantiate() as SkillCard
	add_child_autofree(card)
	card.configure(multiplier, target)
	assert_string_contains(card.preview_label.text, "+0.4 → +0.6")
	card.configure_catalog(multiplier, _run)
	assert_string_contains(card.effect_label.text, "0.4")
	assert_false(card.preview_label.text.contains("0.6"))
	assert_false(card.action_label.visible)
	var column: SkillDefinition = _skill("line_column_span")
	_run.state.line_clear.column_unlocked = true
	AestheticCases.install(_run, column)
	assert_eq(_run.state.rule_error, "")
	assert_eq(SkillRules.level(_run.state, column), 1)
	assert_string_contains(SkillPoolText.rule_view(_run, column).context, "Lv.1")
	assert_false(SkillPoolText.rule_view(_run, column).text.contains("Manual rule"), "max level reads its owned config, not an absent next level")
	var refill: SkillDefinition = _skill("refill_less")
	_run.state.spawning.extend_refill(-1, 3)
	assert_string_contains(SkillPoolText.rule_view(_run, refill).context, "Definition only", "another card's shared modifier is not ownership")
	_run.state.rewards.acquired[refill.skill_id] = 1
	assert_string_contains(SkillPoolText.rule_view(_run, refill).text, "3 actual refills remaining")
	for index: int in range(3): _run.state.spawning.consume_refill_count(RunController.SPAWN_CONFIG)
	assert_string_contains(SkillPoolText.rule_view(_run, refill).context, "Definition only")
	var unsupported: SkillDefinition = _skill("line_manual_clear")
	assert_string_contains(SkillPoolText.rule_view(_run, unsupported).text, "[Manual rule]")

func test_real_pool_bilingual_views_keep_context_bodies_metadata_and_six_rngs_unchanged() -> void:
	_run.state.explosion.multiplier_level = 3
	var original: String = RunSnapshot.digest(RunSnapshot.capture(_run))
	var config: String = RunSnapshot.digest(RunSnapshot.config(_run))
	var pool: SkillPool = POOL.instantiate() as SkillPool
	add_child_autofree(pool)
	pool.open(_run)
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		await wait_process_frames(4)
		assert_eq(pool.entries.get_child_count(), 52)
		for child: Node in pool.entries.get_children():
			var card: SkillCard = child as SkillCard
			var view: Dictionary[String, String] = SkillPoolText.rule_view(_run, card._skill)
			assert_eq(card.effect_label.text, view.text)
			assert_string_contains(card.preview_label.text, view.context)
			assert_string_contains(card.preview_label.text, card.tr("前置：%s").get_slice("%s", 0))
			assert_false(card.preview_label.text.contains("rules.context"))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(_run)), original)
		assert_eq(RunSnapshot.digest(RunSnapshot.config(_run)), config)
	pool.close()

func test_pool_scrolling_reaches_rule_context_and_return_control_at_both_viewports() -> void:
	_run.state.explosion.multiplier_level = 3
	AestheticCases.install(_run, _skill("composite_refill_color"))
	assert_eq(_run.state.rule_error, "")
	var before: String = RunSnapshot.digest(RunSnapshot.capture(_run))
	var pool: SkillPool = POOL.instantiate() as SkillPool
	add_child_autofree(pool)
	pool.apply_game_theme(GameThemes.ALL[0])
	pool.open(_run)
	for size: Vector2i in [Vector2i(1024, 640), Vector2i(1280, 720)]:
		get_window().size = size
		get_window().content_scale_size = size
		for locale: String in ["en_US", "zh_CN"]:
			TranslationServer.set_locale(locale)
			await wait_process_frames(5)
			for id: String in ["line_column_span", "composite_refill_color"]:
				var card: SkillCard = _find_card(pool, StringName(id))
				assert_not_null(card)
				pool.scroll.scroll_vertical = int(card.position.y)
				await wait_process_frames(3)
				assert_true(pool.scroll.get_global_rect().intersects(card.effect_label.get_global_rect()))
				assert_false(card.effect_label.text.contains("rules."))
				if OS.get_environment("O4_POOL_CAPTURE") == "1":
					var directory: String = "res://.godot/o4-pool-captures"
					assert_eq(DirAccess.make_dir_recursive_absolute(directory), OK)
					assert_eq(get_viewport().get_texture().get_image().save_png(directory + "/%s_%d_%s.png" % [locale, size.x, id]), OK)
				pool.scroll.scroll_vertical = int(card.preview_label.global_position.y - pool.entries.global_position.y - 8.0)
				await wait_process_frames(3)
				assert_true(pool.scroll.get_global_rect().grow(1).encloses(card.preview_label.get_global_rect()), "%s %s %s" % [locale, size, id])
				assert_true(get_viewport().get_visible_rect().encloses(pool.close_button.get_global_rect()))
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(_run)), before)
	pool.close()

func _find_card(pool: SkillPool, id: StringName) -> SkillCard:
	for child: Node in pool.entries.get_children():
		var card: SkillCard = child as SkillCard
		if card._skill.skill_id == id: return card
	return null
