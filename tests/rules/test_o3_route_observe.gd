extends GutTest
## O3 post-acquisition windows. Facts only; nulls kept; no pass-line assertions on rates.

const F: Script = preload("res://tests/support/o3_fixed_fixture.gd")

func test_analyze_marks_immediate_startup_and_keeps_null_synergy() -> void:
	var records: Array[Dictionary] = [
		{"kind": "SkillAcquired", "command_id": "7", "skill_id": "core_drop"},
		{"kind": "RuleResult", "command_id": "7", "events": [{"cause": "explosion", "removed": [{"id": 1}]}]},
		{"kind": "Footer", "status": "censored", "reason": "move_limit"},
	]
	var report: Dictionary = O3RouteObserve.analyze(records, &"B1")
	assert_true(report.acquired)
	assert_eq(report.startup.wait_actions, 0)
	assert_true(report.startup.within_4)
	assert_eq(report.synergy, null)
	assert_string_contains(str(report.telemetry_note), "all_ability_attempts=false")

func test_analyze_counts_player_actions_before_effective_and_growth_offers() -> void:
	var records: Array[Dictionary] = [
		{"kind": "SkillAcquired", "command_id": "1", "skill_id": "line_row_drop"},
		{"kind": "RuleResult", "command_id": "1", "events": []},
		{"kind": "CommandAttempt", "accepted": true, "command": {"type": "move", "command_id": "2"}},
		{"kind": "RuleResult", "command_id": "2", "events": []},
		{"kind": "CommandAttempt", "accepted": true, "command": {"type": "activate_line", "command_id": "3"}},
		{"kind": "RuleResult", "command_id": "3", "events": [{"cause": "line_clear", "removed": [{"id": 2}]}]},
		{"kind": "Offer", "offer": {"choices": ["score_multiplier", "line_clear_score", "blast_extra"]}},
		{"kind": "Offer", "offer": {"choices": ["match_extra", "refill_less", "instant_thin"]}},
		{"kind": "Offer", "offer": {"choices": ["line_row_span", "blast_radius", "core_drop"]}},
		{"kind": "SkillAcquired", "command_id": "9", "skill_id": "line_row_span"},
		{"kind": "Footer", "status": "censored", "reason": "move_limit"},
	]
	var report: Dictionary = O3RouteObserve.analyze(records, &"L1")
	assert_eq(report.startup.wait_actions, 2)
	assert_true(report.startup.within_4)
	assert_true(report.upgrade.window_complete)
	assert_true(report.upgrade.offered)
	assert_true(report.upgrade.taken)
	assert_true(report.upgrade.offered_ids.has("line_clear_score") or report.upgrade.offered_ids.has("line_row_span"))

func test_guard_batch_attaches_windows_without_pass_line() -> void:
	var batch: Dictionary = O3RouteObserve.run_batch(1, 3, 14000, 60)
	assert_eq((batch.failures as Array).size(), 0, str(batch.failures))
	assert_eq(batch.pass_line, null)
	for route_id: StringName in O3BuildRoutes.ORDER:
		var summary: Dictionary = batch.by_route[String(route_id)]
		assert_lte(int(summary.acquired_parents), 1)
		assert_true(summary.windows.has("startup_within_4"))
		assert_true(summary.windows.has("upgrade_offered_in_3"))
	assert_eq(F.write_evidence("route-observe-guard", {"by_route": batch.by_route, "failures": batch.failures}), OK)
