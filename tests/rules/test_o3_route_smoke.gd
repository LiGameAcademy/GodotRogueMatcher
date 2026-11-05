extends GutTest
## O3 per-route smoke. Records facts only; synergy rates are not pass criteria.
## Pre-seeded synthetic offers are outside RuleReplay support; live rule_error is the gate.

const F: Script = preload("res://tests/support/o3_fixed_fixture.gd")

func test_one_game_per_route_has_no_rule_error() -> void:
	var batch: Dictionary = O3RouteSmoke.run_batch(1, 9100, 40)
	assert_eq(batch.games, 6)
	assert_eq((batch.failures as Array).size(), 0, str(batch.failures))
	for route_id: StringName in O3BuildRoutes.ORDER:
		var summary: Dictionary = batch.by_route[String(route_id)]
		assert_eq(summary.games, 1)
		assert_eq(summary.rule_errors, 0)
	assert_eq(F.write_evidence("route-smoke-guard", {"games": batch.games, "failures": batch.failures,
		"by_route": batch.by_route}), OK)
	print("O3_SMOKE_GUARD ", JSON.stringify({"games": batch.games, "failures": (batch.failures as Array).size(),
		"by_route": batch.by_route}))

func test_full_ten_per_route_smoke_records_facts_without_pass_line() -> void:
	var batch: Dictionary = O3RouteSmoke.run_batch(10, 9200, 60)
	assert_eq(batch.games, 60)
	assert_eq((batch.failures as Array).size(), 0, str(batch.failures))
	for route_id: StringName in O3BuildRoutes.ORDER:
		var summary: Dictionary = batch.by_route[String(route_id)]
		assert_eq(summary.games, 10)
		assert_eq(summary.rule_errors, 0)
		assert_gte(int(summary.synergy_games), 0)
	assert_eq(F.write_evidence("route-smoke-10", {"summary": {"per_route": batch.per_route,
		"start_seed": batch.start_seed, "move_limit": batch.move_limit, "games": batch.games,
		"failures": batch.failures, "by_route": batch.by_route}, "rows": batch.rows}), OK)
	print("O3_SMOKE_10 ", JSON.stringify({"games": batch.games, "failures": (batch.failures as Array).size(),
		"by_route": batch.by_route}))
