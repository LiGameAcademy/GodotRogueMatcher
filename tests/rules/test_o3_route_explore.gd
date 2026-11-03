extends GutTest
## O3 natural acquisition explore. Keeps non-hits; never pads with pre-install; no pass line.

const F: Script = preload("res://tests/support/o3_fixed_fixture.gd")

func test_guard_scan_keeps_misses_and_rejects_preinstall_padding() -> void:
	var batch: Dictionary = O3RouteExplore.run_batch(1, 3, 12100, 40)
	assert_eq((batch.routes as Array).size(), 6)
	assert_eq((batch.failures as Array).size(), 0, str(batch.failures))
	for route_id: StringName in O3BuildRoutes.ORDER:
		var summary: Dictionary = batch.by_route[String(route_id)]
		assert_lte(int(summary.scanned), 3)
		assert_lte(int(summary.acquired_parents), 1)
		assert_eq(int(summary.scanned), (summary.rows as Array).size())
		var misses: int = 0
		for row: Dictionary in summary.rows:
			assert_false(row.source == "fixture/automated")
			assert_eq(row.source, "bot/natural")
			if not row.acquired: misses += 1
		assert_eq(misses + int(summary.acquired_parents), int(summary.scanned))
	assert_eq(F.write_evidence("route-explore-guard", {"failures": batch.failures, "by_route": _compact(batch.by_route)}), OK)

func _compact(by_route: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for route: String in by_route:
		var summary: Dictionary = by_route[route]
		out[route] = {"scanned": summary.scanned, "acquired_parents": summary.acquired_parents,
			"coverage_gap": summary.coverage_gap, "stop_reason": summary.stop_reason,
			"acquisition_rate": summary.acquisition_rate, "failure_count": (summary.failures as Array).size()}
	return out
