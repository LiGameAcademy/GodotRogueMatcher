extends GutTest
## Score projections are checked against real ledger results at multiple levels.

const IDS: Array[StringName] = [&"match_extra", &"blast_extra", &"blast_reward", &"line_clear_score"]
var _locale: String

func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en_US")

func after_each() -> void:
	TranslationServer.set_locale(_locale)

func test_definition_owned_proposed_numbers_and_unsupported_parameters() -> void:
	for locale: String in ["en_US", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for id: StringName in IDS:
			var skill: SkillDefinition = _skill(id)
			for level: int in [1, 2, 3]:
				var result: Dictionary[String, String] = SkillRuleDescription.describe(skill, level, -1, true)
				assert_eq(result.error, "")
				assert_string_contains(result.text, str(_delta(id) * level))
				assert_eq(result.text, SkillChoiceText.summary(skill, level))
			var target: SkillTarget = SkillTarget.new()
			target.level_before = 1
			target.level_after = 2
			target.value_before = 1
			target.value_after = 2
			var preview: String = SkillChoiceText.compact_preview(skill, target)
			assert_string_contains(preview, "+%d" % _delta(id))
			assert_string_contains(preview, "+%d" % (2 * _delta(id)))
			assert_false(preview.contains("rules."))
			assert_eq(SkillRuleDescription.describe(skill).error, "")
			if skill.maximum_level > 0:
				assert_string_contains(SkillRuleDescription.describe(skill, skill.maximum_level + 1).error, "maximum")
	TranslationServer.set_locale("en_US")
	assert_string_contains(SkillChoiceText.summary(_skill(&"match_extra")), "scoring clear")
	assert_string_contains(SkillChoiceText.summary(_skill(&"blast_extra")), "Empty blasts give none")
	assert_string_contains(SkillChoiceText.summary(_skill(&"blast_reward")), "directly")
	assert_string_contains(SkillChoiceText.summary(_skill(&"line_clear_score")), "Excludes the source")
	var changed: SkillDefinition = _skill(&"match_extra").duplicate(true) as SkillDefinition
	(changed.choice_effect as DemolitionStatEffect).stat = DemolitionStatEffect.Stat.RADIUS
	assert_string_contains(SkillRuleDescription.describe(changed).error, "unsupported demolition stat")
	var line: SkillDefinition = _skill(&"line_clear_score").duplicate(true) as SkillDefinition
	(line.acquisition_effect() as InstallLineUpgradeEffect).required_axis = 0
	assert_string_contains(SkillRuleDescription.describe(line).error, "unsupported line upgrade")

func test_match_extra_is_per_result_in_matches_and_scored_short_clears() -> void:
	for level: int in [0, 1, 2, 3]:
		var run: RunController = _run(level)
		for x: int in range(5): run.state.rules.place_piece(Vector2i(x, 0), 0)
		var matches: Array[MatchResult] = run.abilities.resolve(run.state.rules.find_matches())
		assert_eq(matches.size(), 1)
		var entry: ScoreEntry = matches[0].score_entry
		assert_eq(entry.extra_score, level * _delta(&"match_extra"))
		assert_eq(entry.final_score, floori(entry.base_score * entry.multiplier) + entry.extra_score)
		assert_eq(run.state.ledger.total, entry.final_score)
		var piece: PieceState = run.state.rules.place_piece(Vector2i(0, 2), 1)
		var cleared: Array[MatchResult] = run.abilities.resolve_removal([piece, piece], &"skill_clear", false, true)
		assert_eq(cleared.size(), 1)
		assert_eq(cleared[0].removed.size(), 1)
		assert_eq(cleared[0].score_entry.extra_score, entry.extra_score)
		assert_eq(cleared[0].score_entry.base_score, 6)
		var total: int = run.state.ledger.total
		assert_true(run.abilities.resolve_removal([piece], &"skill_clear", false, true).is_empty())
		assert_eq(run.state.ledger.total, total)
		run.retire()

func test_blast_bonuses_follow_direct_removals_and_each_descendant_not_multiplier() -> void:
	for level: int in [0, 1, 2, 3]:
		var run: RunController = _run(level)
		var core: PieceState = run.abilities.add_core(Vector2i(2, 2))
		var fuse: PieceState = run.state.rules.place_piece(Vector2i(3, 2), 0)
		assert_true(run.abilities.assign_fuse(fuse.piece_id))
		run.state.rules.place_piece(Vector2i(2, 3), 2)
		run.state.rules.place_piece(Vector2i(4, 2), 1)
		var results: Array[MatchResult] = run.abilities.resolve_removal([core], &"consume")
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 2)
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].generation, 2)
		var total: int = 0
		for result: MatchResult in results:
			assert_eq(result.score_entry.base_score, 0)
			assert_eq(result.score_entry.extra_score, level * (_delta(&"blast_extra") + result.removed.size() * _delta(&"blast_reward")))
			total += result.score_entry.final_score
		assert_eq(run.state.ledger.total, total)
		var empty: PieceState = run.abilities.add_core(Vector2i(8, 8))
		var empty_results: Array[MatchResult] = run.abilities.resolve_removal([empty], &"consume")
		assert_eq(empty_results.size(), 1)
		assert_true(empty_results[0].removed.is_empty())
		assert_eq(empty_results[0].score_entry.extra_score, 0)
		assert_eq(run.state.ledger.total, total)
		run.retire()

func test_cross_sweep_does_not_count_source_or_blast_descendants_and_tool_is_not_sweep() -> void:
	for level: int in [0, 1, 2, 3]:
		var run: RunController = _run(level)
		run.state.line_clear.upgrades[&"line_cross_upgrade"] = 1
		run.state.line_clear.upgrades[&"line_clear_score"] = level
		var source: PieceState = run.abilities.add_line_piece(LineClearState.AXIS_ROW, Vector2i(4, 4))
		var core: PieceState = run.abilities.add_core(Vector2i(5, 4))
		run.state.rules.place_piece(Vector2i(4, 2), 1)
		run.state.rules.place_piece(Vector2i(6, 5), 2)
		var results: Array[MatchResult] = run.abilities.resolve_removal([source], &"consume")
		assert_eq(results.size(), 2)
		assert_eq(results[0].removed.size(), 2)
		assert_false(results[0].score_entry.target_ids.has(source.piece_id))
		assert_true(results[0].score_entry.target_ids.has(core.piece_id))
		assert_eq(results[0].score_entry.extra_score, level * (_delta(&"match_extra") + 2 * _delta(&"line_clear_score")))
		assert_eq(results[1].removed.size(), 1)
		assert_eq(results[1].score_entry.extra_score, level * (_delta(&"blast_extra") + _delta(&"blast_reward")))
		assert_eq(run.state.ledger.total, results[0].score_entry.final_score + results[1].score_entry.final_score)
		var piece: PieceState = run.state.rules.place_piece(Vector2i(0, 0), 1)
		var tool: Array[MatchResult] = run.abilities.resolve_removal([piece], &"skill_clear", false, true)
		assert_eq(tool[0].score_entry.extra_score, level * _delta(&"match_extra"))
		run.retire()

func _run(level: int) -> RunController:
	var run: RunController = RunController.new(BoardRules.new(BoardState.new(9, 9), 5), 1294)
	run.state.explosion.match_extra_level = level
	run.state.explosion.blast_extra_level = level
	run.state.explosion.reward_level = level
	run.state.explosion.multiplier_level = 5
	return run

func _skill(id: StringName) -> SkillDefinition:
	return load("res://gameplay/progression/content/%s.tres" % id) as SkillDefinition

func _delta(id: StringName) -> int:
	match id:
		&"match_extra": return SkillRuleDescription.EXPLOSION.bonus_per_match
		&"blast_extra": return SkillRuleDescription.EXPLOSION.bonus_per_blast
		&"blast_reward": return SkillRuleDescription.EXPLOSION.reward_per_target
	return LineClearRules.score_per_target(1)
