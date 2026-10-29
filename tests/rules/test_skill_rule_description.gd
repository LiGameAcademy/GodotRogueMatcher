extends GutTest
## D01-D06 semantic contracts; no effect execution is needed to describe a card.

const ROOT: String = "res://gameplay/progression/content/"
var _locale: String

func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en_US")

func after_each() -> void:
	TranslationServer.set_locale(_locale)

func _skill(id: String) -> SkillDefinition:
	return (load(ROOT + id + ".tres") as SkillDefinition).duplicate(true) as SkillDefinition

func test_all_six_use_configuration_in_both_languages() -> void:
	for locale: String in ["en_US", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for id: StringName in SkillRuleDescription.IDS:
			var result: Dictionary[String, String] = SkillRuleDescription.describe(_skill(str(id)))
			assert_eq(result.error, "", "%s %s" % [locale, id])
			assert_false(result.text.contains("rules."))
			assert_false(result.text.contains("人工规则"))
			assert_false(result.text.contains("Manual rule"))

func test_multiplier_is_additive_contribution_and_owned_level_not_final_multiplier() -> void:
	var skill: SkillDefinition = _skill("score_multiplier")
	assert_string_contains(SkillChoiceText.summary(skill), "0.2")
	assert_string_contains(SkillChoiceText.summary(skill, 2, -1, true), "0.4")
	assert_false(SkillChoiceText.summary(skill).contains("20%"))
	var target: SkillTarget = SkillTarget.new()
	target.value_before = 1
	target.value_after = 2
	assert_string_contains(SkillChoiceText.compact_preview(skill, target), "+0.2 → +0.4")
	assert_string_contains(SkillChoiceText.compact_preview(skill, target), "not the final multiplier")

func test_row_range_uses_runtime_formula_and_preserves_edges_and_manual_boundary() -> void:
	var skill: SkillDefinition = _skill("line_row_span")
	var text: String = SkillChoiceText.summary(skill, 1)
	assert_string_contains(text, str(LineClearRules.line_count(1)))
	assert_string_contains(text, "truncated at edges")
	assert_string_contains(text, "grants no manual activation")
	assert_eq(SkillRuleDescription.describe(skill, 1, -1, true).error, "")
	assert_string_contains(SkillRuleDescription.describe(skill, 2).error, "maximum")
	var target: SkillTarget = SkillTarget.new()
	target.level_after = 1
	assert_string_contains(SkillChoiceText.level_text(skill, target), "MAX")

func test_refill_parameters_repeat_remaining_zero_and_net_count_preview() -> void:
	var skill: SkillDefinition = _skill("refill_less")
	var effect: RefillCountEffect = skill.choice_effect as RefillCountEffect
	effect.batches = 7
	assert_string_contains(SkillChoiceText.summary(skill), "7 actual refills")
	assert_string_contains(SkillChoiceText.summary(skill), "not amount")
	assert_string_contains(SkillChoiceText.summary(skill, 1, 2, true), "2 actual refills remaining")
	assert_string_contains(SkillChoiceText.summary(skill, 1, 0, true), "zero")
	assert_string_contains(SkillRuleDescription.describe(skill, 1, -1, true).error, "remaining missing")
	var target: SkillTarget = SkillTarget.new()
	target.value_before = 3
	target.value_after = 3
	target.remaining_before = 2
	target.remaining_after = 9
	var text: String = SkillChoiceText.compact_preview(skill, target)
	assert_string_contains(text, "3 → 3")
	assert_string_contains(text, "2 → 9")
	effect.batches = 0
	assert_string_contains(SkillRuleDescription.describe(skill).error, "invalid refill")

func test_goal_is_next_target_and_reads_changed_resource_value() -> void:
	var skill: SkillDefinition = _skill("goal_score_bonus")
	(skill.acquisition_effect() as InstallGoalBonusEffect).bonus_score = 47
	var text: String = SkillChoiceText.summary(skill)
	assert_string_contains(text, "47")
	assert_string_contains(text, "next stage target")
	assert_string_contains(text, "No retroactive")
	assert_false(SkillChoiceText.summary(skill, 1, -1, true).contains("next stage target"))
	assert_string_contains(text, "unaffected by the score multiplier")

func test_mixed_lifetime_preserves_permanent_weight_after_refill_expires() -> void:
	var skill: SkillDefinition = _skill("composite_refill_color")
	var composite: CompositeEffect = skill.acquisition_effect() as CompositeEffect
	(composite.children[0] as RefillCountEffect).batches = 6
	(composite.children[1] as ColorWeightEffect).delta = 4
	var proposed: String = SkillChoiceText.summary(skill, 1)
	assert_string_contains(proposed, "6 actual refills")
	assert_string_contains(proposed, "weight +4")
	var owned: String = SkillChoiceText.summary(skill, 1, 0, true)
	assert_string_contains(owned, "0 actual refills remaining")
	assert_string_contains(owned, "persists after")
	assert_false(owned.contains("6 actual refills"))

func test_clear_then_dynamic_dye_is_not_a_frozen_promise_and_barrier_is_last() -> void:
	var skill: SkillDefinition = _skill("composite_clear_dye")
	var text: String = SkillChoiceText.summary(skill, 1)
	assert_lt(text.find("Clear a chosen"), text.find("Randomly select"))
	assert_string_contains(text, "up to %d" % DyeRules.CONFIG.instant_targets)
	assert_string_contains(text, "surviving ordinary")
	assert_string_contains(text, "fuses too")
	assert_string_contains(text, "no match base points")
	assert_string_contains(text, "skip if none")
	var targets: CompositeSkillTarget = CompositeSkillTarget.new()
	targets.leaf_targets = [SkillTarget.new(), SkillTarget.new()]
	targets.leaf_targets[1].deferred = true
	assert_string_contains(SkillChoiceText.compact_preview(skill, targets), "after clearing")
	assert_gt(text.find("outermost"), text.find("to dye"))
	var dye: DyeMaterialEffect = (skill.acquisition_effect() as CompositeEffect).children[1] as DyeMaterialEffect
	dye.target_policy = ChoiceEffect.TargetPolicy.FIXED
	assert_string_contains(SkillChoiceText.summary(skill), "identities frozen")
	dye.allow_empty_targets = false
	assert_string_contains(SkillChoiceText.summary(skill), "cannot execute")

func test_nested_order_conditions_and_cycle_diagnostics() -> void:
	var skill: SkillDefinition = _skill("composite_refill_color")
	var root: CompositeEffect = skill.acquisition_effect() as CompositeEffect
	var nested: CompositeEffect = CompositeEffect.new()
	nested.children = root.children.duplicate()
	root.children = [nested]
	assert_eq(SkillRuleDescription.describe(skill).error, "")
	assert_string_contains(SkillChoiceText.summary(skill), "1. Next")
	root.children = [root]
	assert_string_contains(SkillRuleDescription.describe(skill).error, "cycle")
	root.children.clear()
	var conditioned: SkillDefinition = _skill("line_row_span")
	conditioned.levels[0].abilities[0].max_triggers = 1
	assert_string_contains(SkillRuleDescription.describe(conditioned).error, "conditions and limits")

func test_unsupported_missing_parameters_and_translation_return_identifiable_manual_fallback() -> void:
	var other: SkillDefinition = _skill("line_manual_clear")
	assert_string_contains(SkillChoiceText.summary(other), "[Manual rule]")
	assert_string_contains(SkillRuleDescription.describe(other).error, "line_manual_clear")
	var missing: SkillDefinition = _skill("score_multiplier")
	missing.choice_effect = null
	assert_string_contains(SkillRuleDescription.describe(missing).error, "effect missing")
	assert_string_contains(SkillRuleDescription._format("rules.not_installed").error, "translation missing")
	assert_string_contains(SkillRuleDescription._format("rules.goal", {"wrong": 1}).error, "parameter missing")
	var missing_entry: Translation = Translation.new()
	missing_entry.locale = "zh_CN"
	assert_string_contains(SkillRuleDescription._translation_error(missing_entry, "rules.goal"), "translation missing")
	var missing_preview: Dictionary[String, String] = SkillRuleDescription.preview("rules.preview_not_installed")
	assert_string_contains(missing_preview.text, "[Manual preview]")
	assert_string_contains(missing_preview.error, "rules.preview_not_installed")
	var originals: Array[Translation] = []
	for locale: String in ["en_US", "zh_CN"]:
		var translation: Translation = load("res://localization/skill_rules.%s.translation" % locale) as Translation
		originals.append(translation)
		TranslationServer.remove_translation(translation)
	assert_string_contains(SkillRuleDescription.describe(_skill("score_multiplier")).error, "rules.multiplier")
	assert_string_contains(SkillChoiceText.summary(_skill("score_multiplier")), "[Manual rule]")
	for translation: Translation in originals: TranslationServer.add_translation(translation)

func test_rendering_all_contexts_leaves_rule_snapshot_resources_and_rng_unchanged() -> void:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 874)
	run.initialize("description_readonly")
	var before: String = RunSnapshot.digest(RunSnapshot.capture(run))
	var config_before: String = RunSnapshot.digest(RunSnapshot.config(run))
	var random_states: Dictionary[StringName, int] = {}
	for id: StringName in RunRandomStreams.IDS:
		random_states[id] = run.state.random_streams.stream(id).state
	for id: StringName in SkillRuleDescription.IDS:
		var skill: SkillDefinition = load(ROOT + str(id) + ".tres") as SkillDefinition
		var saved: String = skill.description + skill.short_description + skill.flavor_text
		var resource_before: String = RunSnapshot.digest(RunSnapshot.resource_fields(skill))
		for locale: String in ["en_US", "zh_CN"]:
			TranslationServer.set_locale(locale)
			SkillChoiceText.summary(skill)
			SkillChoiceText.summary_rich(skill, 1, 2, true)
		assert_eq(skill.description + skill.short_description + skill.flavor_text, saved)
		assert_eq(RunSnapshot.digest(RunSnapshot.resource_fields(skill)), resource_before)
	assert_eq(RunSnapshot.digest(RunSnapshot.capture(run)), before)
	assert_eq(RunSnapshot.digest(RunSnapshot.config(run)), config_before)
	for id: StringName in random_states:
		assert_eq(run.state.random_streams.stream(id).state, random_states[id])
	run.retire()
