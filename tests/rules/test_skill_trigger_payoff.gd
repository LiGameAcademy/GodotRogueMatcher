extends GutTest

## #88: install-effect cards are not "untriggered" just because window attempts stay 0.

func test_catalog_modes_split_manual_install_and_unknown() -> void:
	assert_eq(SkillTriggerPayoff.mode_for_skill(&"composite_clear_dye"), SkillTriggerPayoff.MODE_INSTALL_EFFECT)
	assert_eq(SkillTriggerPayoff.mode_for_skill(&"line_column_span"), SkillTriggerPayoff.MODE_INSTALL_EFFECT)
	assert_eq(SkillTriggerPayoff.mode_for_skill(&"assign_fuse"), SkillTriggerPayoff.MODE_INSTALL_EFFECT)
	assert_eq(SkillTriggerPayoff.mode_for_skill(&"core_manual_detonation"), SkillTriggerPayoff.MODE_MANUAL)
	assert_eq(SkillTriggerPayoff.mode_for_skill(&"line_manual_clear"), SkillTriggerPayoff.MODE_MANUAL)
	assert_eq(SkillTriggerPayoff.mode_for_skill(&"missing_skill"), SkillTriggerPayoff.MODE_UNKNOWN)

func test_install_uses_read_skill_instance_acquire_counters() -> void:
	var records: Array[Dictionary] = [
		{
			"kind": "Footer",
			"final": {
				"skills": [
					{
						"instance_id": "2",
						"skill_id": "composite_clear_dye",
						"level": "1",
						"abilities": [
							{"ability_id": "composite_clear_dye", "event_type": "skill_acquired", "trigger_count": "1"},
						],
					},
				],
			},
		},
	]
	assert_eq(SkillTriggerPayoff.install_uses_for_skill(records, &"composite_clear_dye"), 1)
	assert_eq(SkillTriggerPayoff.install_uses_for_skill(records, &"other"), 0)
	assert_eq(AbilityTriggerStats.attempts_for_skill(records, &"composite_clear_dye"), 0)
	assert_eq(
		SkillTriggerPayoff.window_missing_reason(records, &"composite_clear_dye"),
		"install_effect_not_recurring")
	assert_eq(SkillTriggerPayoff.window_missing_reason(records, &"core_manual_detonation"), "manual_unused")

func test_recurring_attempts_clear_missing_reason() -> void:
	var records: Array[Dictionary] = [
		{
			"kind": "Footer",
			"final": {"skills": [{"instance_id": "3", "skill_id": "blast_radius", "level": 1, "abilities": []}]},
		},
		{
			"kind": "RuleResult",
			"activations": [
				{"skill_instance_id": "3", "matched": true, "attempt": true, "consumed": true},
			],
		},
	]
	assert_eq(SkillTriggerPayoff.window_missing_reason(records, &"blast_radius"), "")
