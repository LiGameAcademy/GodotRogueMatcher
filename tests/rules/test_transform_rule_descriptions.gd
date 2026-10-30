extends GutTest
## Fixed ordinary transformations project their actual configuration without sampling.

const IDS: Array[StringName] = [&"instant_core_transform", &"instant_row_transform", &"instant_column_transform"]

func test_real_resources_and_changed_counts_are_bilingual_read_only() -> void:
	var previous: String = TranslationServer.get_locale()
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 129)
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var config: String = RunSnapshot.digest(RunSnapshot.config(run))
	for id: StringName in IDS:
		var skill: SkillDefinition = (load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition).duplicate(true) as SkillDefinition
		var effect: TransformMaterialEffect = skill.choice_effect as TransformMaterialEffect
		assert_false(effect.dynamic_targets())
		for locale: String in ["en_US", "zh_CN"]:
			TranslationServer.set_locale(locale)
			for count: int in [1, 2, 3]:
				effect.count = count
				var result: Dictionary[String, String] = SkillRuleDescription.describe(skill)
				assert_eq(result.error, "")
				assert_string_contains(result.text, str(count))
				assert_false(result.text.contains("rules."))
		TranslationServer.set_locale("en_US")
		assert_string_contains(SkillChoiceText.summary(skill), "keeping identity, position and color")
		assert_string_contains(SkillChoiceText.summary(skill), "without replacement")
		assert_string_contains(SkillChoiceText.summary(skill), "Grants no natural supply or manual activation")
		effect.target_policy = ChoiceEffect.TargetPolicy.DYNAMIC
		assert_string_contains(SkillRuleDescription.describe(skill).error, "unsupported transform")
		effect.target_policy = ChoiceEffect.TargetPolicy.FIXED
		effect.count = 0
		assert_string_contains(SkillRuleDescription.describe(skill).error, "unsupported transform")
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config)
	run.retire()
	TranslationServer.set_locale(previous)
