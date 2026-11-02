extends GutTest

## Install≠use: only consumed RuleResult.activations count as trigger uses.

func test_consumed_activations_map_to_skill_and_ignore_install_only() -> void:
	var records: Array[Dictionary] = [
		{
			"kind": "Footer",
			"final": {
				"skills": [
					{"instance_id": "3", "skill_id": "blast_radius", "level": 1, "abilities": []},
					{"instance_id": "4", "skill_id": "refill_less", "level": 1, "abilities": []},
				]
			},
		},
		{
			"kind": "RuleResult",
			"activations": [
				{"skill_instance_id": "3", "ability_id": "on_eliminated_explosion", "consumed": true, "applied": true},
				{"skill_instance_id": "3", "ability_id": "on_eliminated_explosion", "consumed": false, "applied": false},
				{"skill_instance_id": "4", "ability_id": "refill", "consumed": true, "applied": true},
				{"skill_instance_id": "9", "ability_id": "ghost", "consumed": true, "applied": true},
			],
		},
	]
	assert_eq(AbilityTriggerStats.consumed_for_skill(records, &"blast_radius"), 1)
	assert_eq(AbilityTriggerStats.consumed_for_skill(records, &"refill_less"), 1)
	assert_eq(AbilityTriggerStats.consumed_for_skill(records, &"missing"), 0)
	var by_skill: Dictionary[String, int] = AbilityTriggerStats.consumed_by_skill(records)
	assert_eq(by_skill["blast_radius"], 1)
	assert_eq(by_skill["refill_less"], 1)
	assert_false(by_skill.has("ghost"))
