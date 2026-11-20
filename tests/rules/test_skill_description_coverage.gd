extends GutTest
## Runtime Resource audit of the shipped catalog, not a text-based estimate of support.

const EXPECTED: Array[StringName] = [&"score_multiplier", &"line_row_span", &"refill_less", &"goal_score_bonus", &"composite_refill_color", &"composite_clear_dye", &"refill_more", &"color_weight_up", &"color_weight_down", &"line_column_span", &"instant_color_clear", &"instant_color_dye", &"match_extra", &"blast_extra", &"blast_reward", &"line_clear_score", &"instant_core_transform", &"instant_row_transform", &"instant_column_transform"]
var _locale: String

func before_each() -> void:
	_locale = TranslationServer.get_locale()

func after_each() -> void:
	TranslationServer.set_locale(_locale)

func test_audit_all_52_real_effect_roots_and_declared_levels() -> void:
	assert_eq(SkillOfferGenerator.CATALOG.size(), 52)
	var records: Array[Dictionary] = []
	var generated: int = 0
	for skill: SkillDefinition in SkillOfferGenerator.CATALOG:
		var item: Dictionary = {"skill_id": String(skill.skill_id), "resource": skill.resource_path, "levels": [], "generated": EXPECTED.has(skill.skill_id)}
		var last_level: int = maxi(1, skill.maximum_level)
		for level: int in range(1, last_level + 1):
			var root: SkillEffect = skill.acquisition_effect(level - 1)
			var entry: Dictionary = {"level": level, "effect": _tree(root), "locales": {}}
			for locale: String in ["zh_CN", "en_US"]:
				TranslationServer.set_locale(locale)
				var result: Dictionary[String, String] = SkillRuleDescription.describe(skill, level)
				assert_eq(result.error.is_empty(), EXPECTED.has(skill.skill_id), "%s %s Lv%d: %s" % [skill.skill_id, locale, level, result.error])
				if not result.error.is_empty(): assert_string_contains(result.text, "[人工规则]" if locale == "zh_CN" else "[Manual rule]")
				entry.locales[locale] = result
			item.levels.append(entry)
		if item.generated: generated += 1
		records.append(item)
	assert_eq(generated, 19)
	var file: FileAccess = FileAccess.open("res://.godot/o4-pool-coverage.json", FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify({"catalog_size": records.size(), "generated": generated, "manual_fallback": records.size() - generated, "cards": records}, "\t"))
		file.flush()
		assert_eq(file.get_error(), OK)
		file.close()

func test_same_family_parameters_and_weight_lifetime_are_not_copied_or_accumulated_per_color() -> void:
	TranslationServer.set_locale("en_US")
	for id: String in ["color_weight_up", "color_weight_down"]:
		var skill: SkillDefinition = (load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition).duplicate(true) as SkillDefinition
		(skill.choice_effect as ColorWeightEffect).delta = -7
		var text: String = SkillChoiceText.summary(skill, 3, 0, true)
		assert_string_contains(text, "-7")
		assert_false(text.contains("-21"), "acquisitions may affect different colors")
		assert_false(text.contains("refill expiry"), "standalone weight has no refill child")
		assert_string_contains(text, "offer fixes")
		assert_string_contains(text, "other colors")
	var refill: SkillDefinition = load("res://gameplay/progression/content/refill_more.tres") as SkillDefinition
	assert_string_contains(SkillChoiceText.summary(refill), "+1")
	var column: SkillDefinition = load("res://gameplay/progression/content/line_column_span.tres") as SkillDefinition
	assert_string_contains(SkillChoiceText.summary(column), "columns")
	assert_string_contains(SkillChoiceText.summary(column), str(LineClearRules.line_count(1)))
	assert_string_contains(SkillChoiceText.summary(column), "truncated at edges")
	var fixed_dye: SkillDefinition = load("res://gameplay/progression/content/instant_color_dye.tres") as SkillDefinition
	assert_string_contains(SkillChoiceText.summary(fixed_dye), "offer freezes")
	assert_string_contains(SkillChoiceText.summary(fixed_dye), "stale target rejects")
	assert_string_contains(SkillChoiceText.summary(fixed_dye), "fuses included")

func _tree(effect: SkillEffect) -> Dictionary:
	if effect == null: return {"missing": true}
	var script: Script = effect.get_script() as Script
	var result: Dictionary = {"class": String(script.get_global_name()), "script": script.resource_path}
	result["parameters"] = RunSnapshot.resource_fields(effect)
	if effect is CompositeEffect:
		var children: Array[Dictionary] = []
		for child: SkillEffect in (effect as CompositeEffect).children: children.append(_tree(child))
		result["children"] = children
	if effect is ChoiceEffect: result["target_policy"] = (effect as ChoiceEffect).target_policy
	return result
