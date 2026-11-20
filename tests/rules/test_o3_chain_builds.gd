extends GutTest
## O3 B2/L2 fixed causality. Fixture/automated only; no natural formation or balance claims.

const C: Script = preload("res://tests/support/o3_chain_fixture.gd")
const F: Script = preload("res://tests/support/o3_fixed_fixture.gd")

func test_b2_effective_fuse_chain_keeps_parent_generations_and_hits() -> void:
	var report: Dictionary = C.blast_chain(41, true)
	assert_true(report.accepted, report.reason)
	assert_gte(report.generations.size(), 2)
	var first_gen: int = int(str(report.generations[0].generation))
	var second_gen: int = int(str(report.generations[1].generation))
	assert_gt(first_gen, 0)
	assert_eq(second_gen, first_gen + 1)
	assert_gt(int(report.generations[0].removed), 0)
	assert_gt(int(report.generations[1].removed), 0)
	var fused_hit: bool = false
	for match_data: Dictionary in report.matches:
		for piece_data: Dictionary in match_data.removed:
			if int(piece_data.id) == int(report.fuse_id): fused_hit = true
	assert_true(fused_hit, "core blast must remove the marked fuse carrier")
	assert_gt(report.traces.size(), 0)
	var linked: bool = false
	for index: int in range(1, report.traces.size()):
		if int(report.traces[index].parent_event_id) == int(report.traces[index - 1].event_id):
			linked = true
			break
	assert_true(linked, "descendant ability events must keep parent ids")
	assert_eq(F.write_evidence("b2-effective-chain", report), OK)
	print("O3_B2 ", JSON.stringify({"effective": true, "generations": report.generations.size(),
		"gen1_removed": report.generations[1].removed, "score": report.final.score}))

func test_b2_empty_descendant_proves_rule_chain_without_effective_payoff() -> void:
	var report: Dictionary = C.blast_chain(41, false)
	assert_true(report.accepted, report.reason)
	assert_gte(report.generations.size(), 2)
	assert_eq(int(report.generations[1].removed), 0, "empty second-generation blast is rule-chain only")
	assert_eq(F.write_evidence("b2-empty-chain", report), OK)
	print("O3_B2 ", JSON.stringify({"effective": false, "generations": report.generations.size(),
		"gen1_removed": report.generations[1].removed, "score": report.final.score}))

func test_l2_cross_upgrade_adds_exclusive_axis_hits_without_double_count() -> void:
	var baseline: Dictionary = C.cross_sweep(55, false)
	var upgraded: Dictionary = C.cross_sweep(55, true)
	assert_true(baseline.accepted, baseline.reason)
	assert_true(upgraded.accepted, upgraded.reason)
	assert_eq(baseline.row_hits, 2)
	assert_eq(baseline.exclusive_hits, 0)
	assert_eq(str(baseline.cross_radius), "-1")
	assert_eq(upgraded.row_hits, 2)
	assert_eq(upgraded.exclusive_hits, 2)
	assert_ne(str(upgraded.cross_radius), "-1")
	var baseline_removed: int = (baseline.matches[0].removed as Array).size()
	var upgraded_removed: int = (upgraded.matches[0].removed as Array).size()
	assert_eq(baseline_removed, 2)
	assert_eq(upgraded_removed, 4)
	assert_eq(upgraded_removed, baseline.row_hits + upgraded.exclusive_hits)
	assert_eq(F.write_evidence("l2-cross-pair", {"baseline": baseline, "upgraded": upgraded}), OK)
	print("O3_L2 ", JSON.stringify({"baseline_removed": baseline_removed, "upgraded_removed": upgraded_removed,
		"exclusive_hits": upgraded.exclusive_hits, "cross_radius": upgraded.cross_radius}))

func test_l2_shipped_cross_fixture_replays_from_disk() -> void:
	var report: Dictionary = C.shipped_cross_replay()
	assert_true(report.accepted, report.reason)
	assert_eq(report.matches.size(), 4)
	assert_true(report.replay_ok, report.replay_error)
	assert_true(report.replay_complete)
	assert_eq(F.write_evidence("l2-shipped-cross-summary", report), OK)

func test_m1_blast_can_start_line_sweep_with_recorded_choice_cost() -> void:
	var report: Dictionary = C.blast_starts_line(63, true)
	assert_true(report.accepted, report.reason)
	assert_true(report.has_line_clear)
	assert_eq(report.sweep_hits, 2)
	assert_eq(report.choices_consumed, 1)
	assert_gte(report.generations.size(), 2)
	assert_eq(F.write_evidence("m1-blast-starts-line", report), OK)
	print("O3_M1 ", JSON.stringify({"hit_line": true, "sweep_hits": report.sweep_hits,
		"choices": report.choices_consumed, "score": report.final.score}))

func test_m1_blast_misses_distant_line_without_false_synergy() -> void:
	var report: Dictionary = C.blast_starts_line(63, false)
	assert_true(report.accepted, report.reason)
	assert_false(report.has_line_clear)
	assert_eq(report.sweep_hits, 0)
	assert_eq(F.write_evidence("m1-blast-misses-line", report), OK)
	print("O3_M1 ", JSON.stringify({"hit_line": false, "has_line_clear": report.has_line_clear,
		"matches": report.matches.size(), "score": report.final.score}))

func test_m2_line_can_start_effective_blast_chain() -> void:
	var report: Dictionary = C.line_starts_blast(64, true)
	assert_true(report.accepted, report.reason)
	assert_true(report.has_line_clear)
	assert_gt(report.blast_removed, 0)
	assert_eq(report.blast_hits, 2)
	assert_eq(report.choices_consumed, 1)
	assert_gte(report.generations.size(), 2)
	assert_eq(F.write_evidence("m2-line-starts-blast", report), OK)
	print("O3_M2 ", JSON.stringify({"effective": true, "blast_hits": report.blast_hits,
		"choices": report.choices_consumed, "score": report.final.score}))

func test_m2_line_to_empty_blast_is_rule_chain_only() -> void:
	var report: Dictionary = C.line_starts_blast(64, false)
	assert_true(report.accepted, report.reason)
	assert_true(report.has_line_clear)
	assert_eq(report.blast_removed, 0)
	assert_eq(report.blast_hits, 0)
	assert_gte(report.generations.size(), 2)
	assert_eq(F.write_evidence("m2-line-empty-blast", report), OK)
	print("O3_M2 ", JSON.stringify({"effective": false, "blast_removed": report.blast_removed,
		"generations": report.generations.size(), "score": report.final.score}))
