extends GutTest

## Sparse-skill paired windows must land on real rare offers, not invent pool supply.

func _job() -> Script:
	return load("res://tools/bot_testing/paired_job.gd") as Script

func test_offer_rarity_filter_uses_catalog_not_invented_ids() -> void:
	var job: Script = _job()
	assert_true(job.offer_meets_min_rarity(["match_extra", "instant_percent_clear"], 2))
	assert_false(job.offer_meets_min_rarity(["match_extra", "core_drop"], 2))
	assert_true(job.offer_meets_min_rarity(["match_extra", "core_drop"], 0))
	assert_false(job.offer_meets_min_rarity(["not_a_real_skill"], 2))
	assert_eq(job.catalog_skill("instant_percent_clear").rarity, 2)

func test_prefix_until_offer_skips_common_only_checkpoints() -> void:
	var job: Script = _job()
	var records: Array[Dictionary] = [
		{"kind": "Header", "seed": "1"},
		{"kind": "Checkpoint", "state": {"offer": {"choices": ["match_extra", "core_drop"]}}},
		{"kind": "Checkpoint", "state": {"offer": {"choices": ["score_multiplier", "instant_percent_clear", "line_row_drop"]}}},
		{"kind": "Footer"},
	]
	var common: Array[Dictionary] = job.prefix_until_offer(records, 0)
	assert_eq(common.size(), 2)
	assert_eq(common.back().state.offer.choices[0], "match_extra")
	var rare: Array[Dictionary] = job.prefix_until_offer(records, 2)
	assert_eq(rare.size(), 3)
	assert_true(rare.back().state.offer.choices.has("instant_percent_clear"))
	assert_true(job.prefix_until_offer(records, 4).is_empty())
